# Generative images and documents

## Create area and chat
A new Create destination provides Document and Image workflows, a prompt, format/filename and a granted destination folder. Documents are drafted through the existing selected chat provider, then use a reviewed createDocument action to serialize the complete content locally. Images prepare a direct reviewed generateImage action without an extra chat-model call. Successful outputs become persisted file cards in chat; PNG/JPEG/WebP cards now show locally downsampled previews.

Chat can request the same actions naturally. Existing assistant answers have an Export menu for PDF, rich text, HTML, Markdown and plain text, using a native save dialog and no additional model request. Exported files receive chat cards too.

## Document formats
- PDF: actual multipage PDF using CoreText/CoreGraphics, with margins, basic Markdown headings, emphasis, lists and Unicode.
- RTF: actual rich-text serialization with the same basic styling.
- HTML: a self-contained offline document with the existing sanitized Markdown/KaTeX renderer and bundled fonts. Use this format for fully typeset LaTeX.
- Markdown, plain text and CSV: UTF-8 files.
- JSON: parsed for validity before saving.

Document content is limited to 100 KB and PDFs to 100 pages. Native Office files (DOCX/XLSX/PPTX), audio and video generation are not implemented. Plain-text write actions reject common binary extensions rather than producing fake PDFs, Office documents or raster images. Document creation still uses the reviewed, granted-folder action system. Existing destinations can be replaced only through the explicit review/save flow.

## Image generation
Images use OpenAI's Images API with a separate developer API key stored in this Mac's Keychain. ChatGPT sign-in OAuth tokens are never sent to the Images API. Configuration is available under Create → Image → Image provider setup, or Settings → Creation. The default image model is gpt-image-2.5-flare; gpt-image-2.5-sunburst is also offered. One PNG is requested at 1024×1024 and low quality.

The review sheet shows the prompt, destination, selected model and separate API-billing notice before generation. The API may require billing, organization verification or model access. An HTTP failure returns an actionable error; it never produces a fake file. This build supports text-to-image generation, not reference-image editing.

Images require a new .png filename and do not overwrite existing images. After the network request, the destination is validated again and the folder must still be granted. Raster responses are decoded and re-encoded as PNG before saving. Long actions show the existing task status and elapsed time; Stop cancels the client task. Provider-side charges may still occur after cancellation.

## Identity and validation
Iris.md and the action contract describe the real supported formats, the separate image credential/billing requirement and the need to wait for successful creation before claiming a file exists.

The final Debug build succeeded; all 60 focused tests passed. New tests validate multipage PDF output and text extraction, real RTF encoding, JSON rejection, supported-format/size bounds, and actual PNG decoding/rejection. A five-page local PDF fixture was rendered and visually inspected for headings, emphasis, lists, Unicode, margins and pagination. Strict signature verification passed. No model allowance or paid image request was used. Live provider generation, API-key entry and a full Create UI walkthrough remain unverified.

Primary references:
- https://developers.openai.com/api/docs/guides/image-generation
- https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations (ChatGPT sign-in does not support hosted image generation)
