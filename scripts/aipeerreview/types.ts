/**
 * Shared type definitions for AI Peer Review
 */

export interface ModelConfig {
  name: string;
  description: string;
  strengths: string[];
}

export interface ReviewTypeConfig {
  models: string[];
  focusAreas: string[];
}

export interface ReviewFile {
  path: string;
  displayName: string;
  language: string;
  content: string;
}

export interface ReviewJob {
  files: ReviewFile[];
  reviewType: string;
  displayName: string;
  combinedContent: string;
}

export interface ModelReviewResult {
  modelId: string;
  modelName: string;
  ok: boolean;
  content?: string;
  error?: string;
  durationMs?: number;
}

export interface LLMClientConfig {
  baseUrl: string;
  apiKey: string;
  timeoutMs?: number;
  maxTokens?: number;
}

export type ReviewErrorKind = 'Config' | 'IO' | 'Network' | 'Api' | 'Timeout' | 'Validation';

export class ReviewError extends Error {
  constructor(
    public readonly kind: ReviewErrorKind,
    message: string,
    public readonly details?: unknown
  ) {
    super(message);
    this.name = 'ReviewError';
  }
}
