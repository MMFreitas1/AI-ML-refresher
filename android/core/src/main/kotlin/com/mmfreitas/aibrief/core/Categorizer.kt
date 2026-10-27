package com.mmfreitas.aibrief.core

/** Deterministic keyword rules. The first matching field wins, so more specific fields come first. */
object Categorizer {
    private val rules: List<Pair<Field, List<String>>> = listOf(
        Field.Neuro to listOf("connectom", "neuroscien", "brain", "neuron", "fmri", "eeg", "cortex", "cortical",
            "spiking", "neuromorph", "bci", "synap", "hippocamp", "drosophila", "neural recording"),
        Field.Robotics to listOf("robot", "humanoid", "manipulation", "locomotion", "vla", "vision-language-action",
            "embodied", "drone", "autonomous driving", "self-driving", "lerobot", "sim2real",
            "sim-to-real", "grasp", "quadruped", "teleoperation"),
        Field.Audio to listOf("audio", "speech", "tts", "asr", "voice", "music", "sound", "whisper",
            "text-to-speech", "speaker", "singing"),
        Field.Video to listOf("video", "3d", "4d", "gaussian splatting", "nerf", "world model", "text-to-video",
            "mesh", "point cloud", "avatar", "animation"),
        Field.Vision to listOf("vision", "image", "segmentation", "detection", "diffusion", "ocr", "vlm", "visual",
            "pixel", "yolo", "depth estimation", "multimodal", "photo", "text-to-image", "vit"),
        Field.Rl to listOf("reinforcement learning", "rl", "policy optimization", "ppo", "grpo", "reward",
            "gym", "mdp", "bandit", "q-learning", "rollout"),
        Field.Agents to listOf("agent", "agents", "agentic", "mcp", "tool use", "tool-use", "browser use",
            "computer use", "coding assistant", "claude code", "codex", "workflow automation"),
        Field.Systems to listOf("inference", "quantiz", "cuda", "gpu", "kernel", "serving", "vllm", "compiler",
            "distributed training", "fp4", "fp8", "llama.cpp", "mlx", "triton", "throughput",
            "latency", "sglang", "ollama", "tpu", "accelerat"),
        Field.Llm to listOf("llm", "language model", "gpt", "claude", "gemini", "llama", "qwen", "mistral",
            "deepseek", "transformer", "token", "reasoning", "rag", "retrieval", "chatbot",
            "prompt", "nlp", "fine-tun", "finetun", "lora", "embedding", "distillation", "chat"),
    )

    /** Terms that mark a generic item (HN story, GitHub repo) as AI/ML related.
     *  Kept stricter than the field rules: words like "kernel" or "image" alone are not enough. */
    private val aiTerms = listOf(
        "ai", "a.i.", "artificial intelligence", "machine learning", "deep learning", "neural",
        "llm", "llms", "gpt", "chatgpt", "claude", "gemini", "llama", "qwen", "deepseek", "mistral",
        "openai", "anthropic", "deepmind", "hugging face", "huggingface", "pytorch", "tensorflow",
        "jax", "transformer", "transformers", "diffusion", "language model", "ai agent", "agentic",
        "rag", "fine-tun", "finetun", "lora", "embeddings", "reinforcement learning",
        "computer vision", "robot", "robotics", "humanoid", "connectom", "mcp", "vllm", "ollama",
        "llama.cpp", "stable diffusion", "sora", "copilot", "text-to-speech", "speech recognition",
        "vlm", "multimodal", "world model", "inference", "model context protocol", "coding agent",
        "grok", "kimi", "glm", "mlx", "rlhf", "gguf", "neuromorphic",
    )

    private val stems = setOf(
        "connectom", "neuroscien", "neuron", "synap", "hippocamp", "neuromorph", "robot", "quantiz",
        "accelerat", "fine-tun", "finetun", "cortic", "embodied", "agent", "transformer", "embedding",
    )

    fun fieldFor(text: String): Field {
        val t = text.lowercase()
        for ((field, words) in rules) if (words.any { contains(t, it) }) return field
        return Field.General
    }

    fun isAIRelated(text: String): Boolean {
        val t = text.lowercase()
        return aiTerms.any { contains(t, it) }
    }

    /** Matches [word] at a word start. Terms ending in a letter must also end at a word boundary, except
     *  stems that are meant as prefixes ("quantiz", "connectom"), which are matched loosely. */
    internal fun contains(text: String, word: String): Boolean {
        var from = 0
        while (true) {
            val i = text.indexOf(word, from)
            if (i < 0) return false
            val end = i + word.length
            val startOK = i == 0 || !text[i - 1].isLetterOrDigit()
            val endOK = end == text.length || !text[end].isLetterOrDigit() || word in stems || pluralAt(text, end)
            if (startOK && endOK) return true
            from = end
        }
    }

    /** Allows a single trailing "s" so "llms", "agents", "models" match their singular rule. */
    private fun pluralAt(text: String, i: Int) =
        text[i] == 's' && (i + 1 == text.length || !text[i + 1].isLetterOrDigit())
}
