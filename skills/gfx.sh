#!/bin/bash
# Professional Graphic Design Skill for Claude
# Advanced image generation, editing, and enhancement using ComfyUI

set -e

COMFY_API="http://10.0.1.226:8188"
OUTPUT_DIR="/tmp/gfx-output"
mkdir -p "$OUTPUT_DIR"

# Usage info
usage() {
    cat << EOF
🎨 Advanced Graphic Design Skill

USAGE:
  /gfx generate "prompt" [options]
  /gfx inpaint image.png --mask mask.png --prompt "edit description"
  /gfx upscale image.png --scale 4
  /gfx control image.png --type canny --prompt "new style"
  /gfx list-models
  /gfx status

OPTIONS:
  --model NAME      Model to use (realistic, dreamshaperXL, anime)
  --size WxH        Image size (default: 1024x1024)
  --steps N         Sampling steps (default: 30)
  --cfg SCALE       CFG scale (default: 7.5)
  --seed N          Random seed (default: random)
  --strength N      Strength for img2img (default: 0.8)
  --scale N         Upscale factor (default: 4)
  --type TYPE       ControlNet type (canny, openpose, depth, tile)
  --output PATH     Output file path

MODELS AVAILABLE:
  realistic       - Realistic Vision V5.1 (photorealistic, high detail)
  dreamshaper     - DreamShaper 8 (versatile, artistic)
  anime           - Counterfeit V3 (anime/manga style)
  sdxl            - Stable Diffusion XL (highest quality)
  inpaint         - Realistic Vision Inpainting (professional editing)

EXAMPLES:
  # Generate professional portrait
  /gfx generate "professional headshot, studio lighting, sharp focus" --model realistic

  # Edit specific area
  /gfx inpaint photo.png --mask face_mask.png --prompt "blue eyes"

  # Upscale 4x
  /gfx upscale lowres.png --scale 4

  # Edge-guided style transfer
  /gfx control original.png --type canny --prompt "cyberpunk style"

EOF
}

# Map friendly names to model files
get_model_file() {
    case "$1" in
        realistic) echo "realisticVisionV51.safetensors" ;;
        dreamshaper) echo "dreamshaper8.safetensors" ;;
        anime) echo "counterfeit_v30.safetensors" ;;
        sdxl) echo "sd_xl_base_1.0.safetensors" ;;
        inpaint) echo "realisticVision_inpainting.safetensors" ;;
        *) echo "realisticVisionV51.safetensors" ;;
    esac
}

# List available models
list_models() {
    echo "📦 Available Models on ComfyUI:"
    echo "==============================="
    echo ""
    echo "GENERATION:"
    curl -s "$COMFY_API/object_info/CheckpointLoaderSimple" | \
        jq -r '.CheckpointLoaderSimple.input.required.ckpt_name[0][]' | \
        grep -E "(realistic|dreamshaper|counterfeit|sd_xl)" | \
        sed 's/^/  ✅ /'
    echo ""
    echo "CONTROLNET:"
    find /tmp -name "control_*.pth" 2>/dev/null | xargs -n1 basename | sed 's/^/  ✅ /' || echo "  (checking...)"
    echo ""
}

# Check ComfyUI status
check_status() {
    echo "🔍 ComfyUI Status:"
    if curl -sf "$COMFY_API/system_stats" > /dev/null; then
        echo "  ✅ ComfyUI is running"
        curl -s "$COMFY_API/system_stats" | jq -r '
            "  📦 Version: " + .system.comfyui_version,
            "  🎮 GPU: " + .devices[0].name,
            "  💾 VRAM: " + ((.devices[0].vram_free / 1024 / 1024 / 1024 * 10 | floor) / 10 | tostring) + "GB free / " + ((.devices[0].vram_total / 1024 / 1024 / 1024 * 10 | floor) / 10 | tostring) + "GB total"
        '
    else
        echo "  ❌ ComfyUI is not responding"
        exit 1
    fi
}

# Generate image
generate_image() {
    local prompt="$1"
    local model="${2:-realistic}"
    local size="${3:-1024x1024}"
    local steps="${4:-30}"
    local cfg="${5:-7.5}"
    local seed="${6:-$(shuf -i 1-4294967295 -n 1)}"

    local width=$(echo $size | cut -d'x' -f1)
    local height=$(echo $size | cut -d'x' -f2)
    local model_file=$(get_model_file "$model")

    echo "🎨 Generating image..."
    echo "   Prompt: $prompt"
    echo "   Model: $model ($model_file)"
    echo "   Size: ${width}x${height}"
    echo "   Steps: $steps, CFG: $cfg, Seed: $seed"
    echo ""

    # Create simplified ComfyUI workflow
    local workflow=$(cat <<WORKFLOW
{
    "3": {
        "inputs": {
            "seed": $seed,
            "steps": $steps,
            "cfg": $cfg,
            "sampler_name": "euler_ancestral",
            "scheduler": "karras",
            "denoise": 1,
            "model": ["4", 0],
            "positive": ["6", 0],
            "negative": ["7", 0],
            "latent_image": ["5", 0]
        },
        "class_type": "KSampler"
    },
    "4": {
        "inputs": {"ckpt_name": "$model_file"},
        "class_type": "CheckpointLoaderSimple"
    },
    "5": {
        "inputs": {"width": $width, "height": $height, "batch_size": 1},
        "class_type": "EmptyLatentImage"
    },
    "6": {
        "inputs": {"text": "$prompt", "clip": ["4", 1]},
        "class_type": "CLIPTextEncode"
    },
    "7": {
        "inputs": {"text": "ugly, blurry, low quality, distorted", "clip": ["4", 1]},
        "class_type": "CLIPTextEncode"
    },
    "8": {
        "inputs": {"samples": ["3", 0], "vae": ["4", 2]},
        "class_type": "VAEDecode"
    },
    "9": {
        "inputs": {"filename_prefix": "gfx", "images": ["8", 0]},
        "class_type": "SaveImage"
    }
}
WORKFLOW
)

    # Queue prompt
    local response=$(curl -s -X POST "$COMFY_API/prompt" \
        -H "Content-Type: application/json" \
        -d "{\"prompt\": $workflow}")

    local prompt_id=$(echo "$response" | jq -r '.prompt_id')

    if [ "$prompt_id" = "null" ] || [ -z "$prompt_id" ]; then
        echo "❌ Error queuing prompt:"
        echo "$response" | jq '.'
        exit 1
    fi

    echo "⏳ Queued (ID: $prompt_id)"
    echo "   Generating..."

    # Poll for completion (timeout 120s)
    local timeout=120
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local history=$(curl -s "$COMFY_API/history/$prompt_id")
        local status=$(echo "$history" | jq -r ".[\"$prompt_id\"].status.status_str" 2>/dev/null)

        if [ "$status" = "success" ]; then
            echo "   ✅ Complete!"

            # Get output filename
            local filename=$(echo "$history" | jq -r ".[\"$prompt_id\"].outputs[\"9\"].images[0].filename")
            local output_path="$OUTPUT_DIR/${filename}"

            # Download image
            curl -s "$COMFY_API/view?filename=$filename" -o "$output_path"

            echo ""
            echo "📁 Output: $output_path"
            echo "🔗 View: file://$output_path"
            echo ""

            # Show image info
            if command -v identify &> /dev/null; then
                identify "$output_path"
            fi

            return 0
        elif [ "$status" = "error" ]; then
            echo "❌ Generation failed"
            echo "$history" | jq ".[\"$prompt_id\"]"
            exit 1
        fi

        sleep 2
        elapsed=$((elapsed + 2))
        echo -ne "   Generating... ${elapsed}s\r"
    done

    echo ""
    echo "❌ Timeout waiting for generation"
    exit 1
}

# Main command router
case "${1:-help}" in
    generate)
        shift
        prompt="$1"
        shift
        generate_image "$prompt" "$@"
        ;;
    list-models|list)
        list_models
        ;;
    status)
        check_status
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 1
        ;;
esac
