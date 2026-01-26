/**
 * LLM API Client for AI Peer Review
 * Abstracts LiteLLM proxy interaction
 */

import type { LLMClientConfig, ModelReviewResult } from "./types";
import { ReviewError } from "./types";
import { ALL_MODELS, REVIEW_TYPE_MODELS, estimateTokens, LIMITS } from "./config";

export class LLMClient {
  private readonly baseUrl: string;
  private readonly apiKey: string;
  private readonly timeoutMs: number;
  private readonly maxTokens: number;

  constructor(config: LLMClientConfig) {
    this.baseUrl = config.baseUrl.replace(/\/$/, ""); // Remove trailing slash
    this.apiKey = config.apiKey;
    this.timeoutMs = config.timeoutMs ?? 300000;
    this.maxTokens = config.maxTokens ?? 4096;
  }

  /**
   * Send a chat completion request to the LLM
   */
  async chatCompletion(
    modelId: string,
    prompt: string
  ): Promise<{ content: string; error?: string }> {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const response = await fetch(`${this.baseUrl}/chat/completions`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: modelId,
          messages: [{ role: "user", content: prompt }],
          max_tokens: this.maxTokens,
        }),
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      if (!response.ok) {
        const errorText = await response.text();
        return {
          content: "",
          error: `HTTP ${response.status}: ${errorText.slice(0, 500)}`,
        };
      }

      const data = (await response.json()) as {
        choices?: Array<{ message?: { content?: string } }>;
        error?: { message?: string };
      };

      if (data.error) {
        return {
          content: "",
          error: data.error.message || "Unknown API error",
        };
      }

      const content = data.choices?.[0]?.message?.content || "";
      return { content };
    } catch (err) {
      clearTimeout(timeoutId);
      if (err instanceof Error && err.name === "AbortError") {
        return {
          content: "",
          error: `Request timed out after ${this.timeoutMs / 1000} seconds`,
        };
      }
      return {
        content: "",
        error: err instanceof Error ? err.message : "Unknown error",
      };
    }
  }

  /**
   * Build a review prompt for a specific model and review type
   */
  buildReviewPrompt(
    modelId: string,
    reviewType: string,
    content: string
  ): string {
    const model = ALL_MODELS[modelId];
    const config = REVIEW_TYPE_MODELS[reviewType];

    if (!model) {
      throw new ReviewError("Config", `Unknown model: ${modelId}`);
    }
    if (!config) {
      throw new ReviewError("Config", `Unknown review type: ${reviewType}`);
    }

    const focusAreasList = config.focusAreas.map((a) => `- ${a}`).join("\n");

    return `You are conducting a ${reviewType.toUpperCase()} peer review. Your expertise: ${model.description}

Focus on these specific areas:
${focusAreasList}

Document to review:
---
${content}
---

Provide a structured review with:
1. **Summary** - One paragraph overview
2. **Strengths** - What's done well (3-5 points)
3. **Issues Found** - Problems ranked by severity (Critical > High > Medium > Low)
4. **Recommendations** - Specific, actionable improvements
5. **Questions** - Clarifications needed from the author

Be concise but thorough. Prioritize actionable feedback over generic advice.`;
  }

  /**
   * Execute a review with a single model
   */
  async reviewWithModel(
    modelId: string,
    content: string,
    reviewType: string
  ): Promise<ModelReviewResult> {
    const model = ALL_MODELS[modelId];
    if (!model) {
      return {
        modelId,
        modelName: modelId,
        ok: false,
        error: `Unknown model: ${modelId}`,
      };
    }

    const startTime = Date.now();
    const prompt = this.buildReviewPrompt(modelId, reviewType, content);

    // Warn about potential token limit issues
    const estimatedTokens = estimateTokens(prompt);
    if (estimatedTokens > LIMITS.MAX_CONTEXT_TOKENS) {
      console.warn(
        `⚠️  Warning: ${model.name} prompt is ~${estimatedTokens} tokens, may exceed context window`
      );
    }

    const { content: result, error } = await this.chatCompletion(modelId, prompt);
    const durationMs = Date.now() - startTime;

    if (error) {
      return {
        modelId,
        modelName: model.name,
        ok: false,
        error,
        durationMs,
      };
    }

    return {
      modelId,
      modelName: model.name,
      ok: true,
      content: result,
      durationMs,
    };
  }

  /**
   * Execute reviews with multiple models in parallel
   */
  async reviewWithModels(
    modelIds: string[],
    content: string,
    reviewType: string
  ): Promise<ModelReviewResult[]> {
    const results = await Promise.allSettled(
      modelIds.map((modelId) => this.reviewWithModel(modelId, content, reviewType))
    );

    return results.map((result, idx) => {
      if (result.status === "fulfilled") {
        return result.value;
      } else {
        const modelId = modelIds[idx];
        return {
          modelId,
          modelName: ALL_MODELS[modelId]?.name || modelId,
          ok: false,
          error: `Promise rejected: ${result.reason}`,
        };
      }
    });
  }
}
