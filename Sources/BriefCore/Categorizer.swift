import Foundation

/// Deterministic keyword rules. The first matching field wins, so more specific fields come first.
public enum Categorizer {
    static let rules: [(Field, [String])] = [
        (.neuro, ["connectom", "neuroscien", "brain", "neuron", "fmri", "eeg", "cortex", "cortical",
                  "spiking", "neuromorph", "bci", "synap", "hippocamp", "drosophila", "neural recording"]),
        (.robotics, ["robot", "humanoid", "manipulation", "locomotion", "vla", "vision-language-action",
                     "embodied", "drone", "autonomous driving", "self-driving", "lerobot", "sim2real",
                     "sim-to-real", "grasp", "quadruped", "teleoperation"]),
        (.audio, ["audio", "speech", "tts", "asr", "voice", "music", "sound", "whisper",
                  "text-to-speech", "speaker", "singing"]),
        (.video, ["video", "3d", "4d", "gaussian splatting", "nerf", "world model", "text-to-video",
                  "mesh", "point cloud", "avatar", "animation"]),
        (.vision, ["vision", "image", "segmentation", "detection", "diffusion", "ocr", "vlm", "visual",
                   "pixel", "yolo", "depth estimation", "multimodal", "photo", "text-to-image", "vit"]),
        (.rl, ["reinforcement learning", "rl", "policy optimization", "ppo", "grpo", "reward",
               "gym", "mdp", "bandit", "q-learning", "rollout"]),
        (.agents, ["agent", "agents", "agentic", "mcp", "tool use", "tool-use", "browser use",
                   "computer use", "coding assistant", "claude code", "codex", "workflow automation"]),
        (.systems, ["inference", "quantiz", "cuda", "gpu", "kernel", "serving", "vllm", "compiler",
                    "distributed training", "fp4", "fp8", "llama.cpp", "mlx", "triton", "throughput",
                    "latency", "sglang", "ollama", "tpu", "accelerat"]),
        (.llm, ["llm", "language model", "gpt", "claude", "gemini", "llama", "qwen", "mistral",
                "deepseek", "transformer", "token", "reasoning", "rag", "retrieval", "chatbot",
                "prompt", "nlp", "fine-tun", "finetun", "lora", "embedding", "distillation", "chat"]),
    ]

    /// Terms that mark a generic item (HN story, GitHub repo) as AI/ML related.
    /// Kept stricter than the field rules: words like "kernel" or "image" alone are not enough.
    static let aiTerms: [String] = [
        "ai", "a.i.", "artificial intelligence", "machine learning", "deep learning", "neural",
        "llm", "llms", "gpt", "chatgpt", "claude", "gemini", "llama", "qwen", "deepseek", "mistral",
        "openai", "anthropic", "deepmind", "hugging face", "huggingface", "pytorch", "tensorflow",
        "jax", "transformer", "transformers", "diffusion", "language model", "ai agent", "agentic",
        "rag", "fine-tun", "finetun", "lora", "embeddings", "reinforcement learning",
        "computer vision", "robot", "robotics", "humanoid", "connectom", "mcp", "vllm", "ollama",
        "llama.cpp", "stable diffusion", "sora", "copilot", "text-to-speech", "speech recognition",
        "vlm", "multimodal", "world model", "inference", "model context protocol", "coding agent",
        "grok", "kimi", "glm", "mlx", "rlhf", "gguf", "neuromorphic",
    ]

    public static func field(for text: String) -> Field {
        let t = text.lowercased()
        for (field, words) in rules where words.contains(where: { contains(t, word: $0) }) {
            return field
        }
        return .general
    }

    public static func isAIRelated(_ text: String) -> Bool {
        let t = text.lowercased()
        return aiTerms.contains { contains(t, word: $0) }
    }

    /// Matches `word` at a word start. Terms ending in a letter must also end at a word boundary,
    /// except stems that are meant as prefixes ("quantiz", "connectom"), which are matched loosely.
    static func contains(_ text: String, word: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let r = text.range(of: word, range: searchRange) {
            let startOK = r.lowerBound == text.startIndex || !text[text.index(before: r.lowerBound)].isLetterOrDigit
            let endOK = r.upperBound == text.endIndex || !text[r.upperBound].isLetterOrDigit
                || isStem(word) || pluralAt(text, r.upperBound)
            if startOK && endOK { return true }
            searchRange = r.upperBound..<text.endIndex
        }
        return false
    }

    private static let stems: Set<String> = [
        "connectom", "neuroscien", "neuron", "synap", "hippocamp", "neuromorph", "robot", "quantiz",
        "accelerat", "fine-tun", "finetun", "cortic", "embodied", "agent", "transformer", "embedding",
    ]

    private static func isStem(_ word: String) -> Bool { stems.contains(word) }

    /// Allows a single trailing "s" so "llms", "agents", "models" match their singular rule.
    private static func pluralAt(_ text: String, _ i: String.Index) -> Bool {
        guard text[i] == "s" else { return false }
        let next = text.index(after: i)
        return next == text.endIndex || !text[next].isLetterOrDigit
    }
}

private extension Character {
    var isLetterOrDigit: Bool { isLetter || isNumber }
}
