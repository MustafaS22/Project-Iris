# Chat attachments

The attachment reader previously treated images as OCR text and rejected pictures without words. The request builders also omitted image bytes. Both are fixed.

## Behavior

- Select up to six files per chat message, with a 20 MB limit per file. Select several in the native picker or add files successively.
- Drag local files from Finder onto the desktop chat or notch message field.
- Use the clipboard button to attach copied Finder files or a copied image. Paste ordinary text directly into the message field.
- Inspect image previews, filenames and extraction notes before Send. Remove individual items. Sending an attachment without a typed message asks Iris to describe or summarize it.
- ImageIO decodes supported image types, honors EXIF orientation and bounds the long edge at 2,048 pixels. Images become JPEG inputs, with a 2 MB cap each. Animated images use their first frame.
- Real image content reaches the latest user turn through Responses input_image, Gemini inlineData, or LM Studio image_url blocks. Vision-capable models are required; text-only local models cannot analyze pictures.
- PDF attachments extract text from up to 40 pages and try local OCR on pages without text. Diagrams in PDFs are not transmitted as images: attach the relevant page as an image for visual analysis.
- Word (.docx), RTF, UTF-8/UTF-16 text and common source-code formats are supported. Empty, binary, corrupt, protected, oversized or unsupported files produce an actionable error.
- Document previews disclose truncation. Multiple documents share a bounded text allowance, ahead of background knowledge, so later attachments are not silently displaced by knowledge context.
- Failures keep attachments for retry; successful responses clear pending chat attachments. Sent messages retain local file cards with Open and Use in question. Original files are not copied to provider storage merely by attaching them. New requests send current attachments; use a file card to reattach material for a later question.
- Pasted image originals live under the app's Application Support/Iris/Chat Attachments folder for reopening from chat.
- Attachment loading cannot complete into a different conversation after that load is cancelled.

## Validation

The app Debug build succeeds. All 68 package tests pass, including eight attachment tests covering non-text images, GIF/TIFF normalization, Word/RTF/PDF extraction, UTF-16, source formats, invalid and oversized files, fair truncation and the three provider payload schemas. No live model requests were made.

The updated app launched and its native multi-file attachment picker opened during the UI smoke check. Further picker automation was interrupted by native UI routing/state changes; no end-to-end provider image response is claimed.

## Provider references

- [OpenAI image inputs](https://developers.openai.com/api/docs/guides/images-vision)
- [Gemini Generate Content image inputs](https://ai.google.dev/gemini-api/docs/generate-content/image-understanding)
