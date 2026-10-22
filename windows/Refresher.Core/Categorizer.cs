namespace Refresher.Core;

/// <summary>Deterministic keyword rules. The first matching field wins, so more specific fields come first.</summary>
public static class Categorizer
{
    static readonly (Field Field, string[] Words)[] Rules =
    [
        (Field.Neuro, ["connectom", "neuroscien", "brain", "neuron", "fmri", "eeg", "cortex", "cortical",
                       "spiking", "neuromorph", "bci", "synap", "hippocamp", "drosophila", "neural recording"]),
        (Field.Robotics, ["robot", "humanoid", "manipulation", "locomotion", "vla", "vision-language-action",
                          "embodied", "drone", "autonomous driving", "self-driving", "lerobot", "sim2real",
                          "sim-to-real", "grasp", "quadruped", "teleoperation"]),
        (Field.Audio, ["audio", "speech", "tts", "asr", "voice", "music", "sound", "whisper",
                       "text-to-speech", "speaker", "singing"]),
        (Field.Video, ["video", "3d", "4d", "gaussian splatting", "nerf", "world model", "text-to-video",
                       "mesh", "point cloud", "avatar", "animation"]),
        (Field.Vision, ["vision", "image", "segmentation", "detection", "diffusion", "ocr", "vlm", "visual",
                        "pixel", "yolo", "depth estimation", "multimodal", "photo", "text-to-image", "vit"]),
        (Field.Rl, ["reinforcement learning", "rl", "policy optimization", "ppo", "grpo", "reward",
                    "gym", "mdp", "bandit", "q-learning", "rollout"]),
        (Field.Agents, ["agent", "agents", "agentic", "mcp", "tool use", "tool-use", "browser use",
                        "computer use", "coding assistant", "claude code", "codex", "workflow automation"]),
        (Field.Systems, ["inference", "quantiz", "cuda", "gpu", "kernel", "serving", "vllm", "compiler",
                         "distributed training", "fp4", "fp8", "llama.cpp", "mlx", "triton", "throughput",
                         "latency", "sglang", "ollama", "tpu", "accelerat"]),
        (Field.Llm, ["llm", "language model", "gpt", "claude", "gemini", "llama", "qwen", "mistral",
                     "deepseek", "transformer", "token", "reasoning", "rag", "retrieval", "chatbot",
                     "prompt", "nlp", "fine-tun", "finetun", "lora", "embedding", "distillation", "chat"]),
    ];

    /// <summary>Terms that mark a generic item (HN story, GitHub repo) as AI/ML related.
    /// Kept stricter than the field rules: words like "kernel" or "image" alone are not enough.</summary>
    static readonly string[] AITerms =
    [
        "ai", "a.i.", "artificial intelligence", "machine learning", "deep learning", "neural",
        "llm", "llms", "gpt", "chatgpt", "claude", "gemini", "llama", "qwen", "deepseek", "mistral",
        "openai", "anthropic", "deepmind", "hugging face", "huggingface", "pytorch", "tensorflow",
        "jax", "transformer", "transformers", "diffusion", "language model", "ai agent", "agentic",
        "rag", "fine-tun", "finetun", "lora", "embeddings", "reinforcement learning",
        "computer vision", "robot", "robotics", "humanoid", "connectom", "mcp", "vllm", "ollama",
        "llama.cpp", "stable diffusion", "sora", "copilot", "text-to-speech", "speech recognition",
        "vlm", "multimodal", "world model", "inference", "model context protocol", "coding agent",
        "grok", "kimi", "glm", "mlx", "rlhf", "gguf", "neuromorphic",
    ];

    static readonly HashSet<string> Stems =
    [
        "connectom", "neuroscien", "neuron", "synap", "hippocamp", "neuromorph", "robot", "quantiz",
        "accelerat", "fine-tun", "finetun", "cortic", "embodied", "agent", "transformer", "embedding",
    ];

    public static Field FieldFor(string text)
    {
        var t = text.ToLowerInvariant();
        foreach (var (field, words) in Rules)
            if (words.Any(w => Contains(t, w))) return field;
        return Field.General;
    }

    public static bool IsAIRelated(string text)
    {
        var t = text.ToLowerInvariant();
        return AITerms.Any(w => Contains(t, w));
    }

    /// <summary>Matches <paramref name="word"/> at a word start. Terms ending in a letter must also end at a word
    /// boundary, except stems that are meant as prefixes ("quantiz", "connectom"), which are matched loosely.</summary>
    internal static bool Contains(string text, string word)
    {
        var from = 0;
        int i;
        while ((i = text.IndexOf(word, from, StringComparison.Ordinal)) >= 0)
        {
            var end = i + word.Length;
            var startOK = i == 0 || !char.IsLetterOrDigit(text[i - 1]);
            var endOK = end == text.Length || !char.IsLetterOrDigit(text[end])
                || Stems.Contains(word) || PluralAt(text, end);
            if (startOK && endOK) return true;
            from = end;
        }
        return false;
    }

    /// <summary>Allows a single trailing "s" so "llms", "agents", "models" match their singular rule.</summary>
    static bool PluralAt(string text, int i) =>
        text[i] == 's' && (i + 1 == text.Length || !char.IsLetterOrDigit(text[i + 1]));
}
