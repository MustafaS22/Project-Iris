# Formatted responses and mathematical notation

Iris now uses one offline response renderer for assistant messages in desktop chat, notch chat, Studio task responses and revealed flashcards. User messages, file previews and proposed source code remain verbatim.

Markdown supports emphasis, headings, lists, tables, links and fenced code blocks. KaTeX renders inline $...$ and \\(...\\), plus display $$...$$ and \\[...\\], including fractions, roots, integrals and matrices. Existing Unicode symbols stay intact. Code blocks preserve their literal contents. Unsupported LaTeX remains visible rather than breaking the response. Shared model instructions now request Markdown and explicit math delimiters.

The renderer bundles Marked 18.1.2, KaTeX 0.19.1, DOMPurify 3.4.17 and all required fonts. It does not need network requests to format responses. Raw HTML is escaped, generated HTML is sanitized, KaTeX trust is disabled, and a content security policy blocks external resources. Ordinary web links open in the default browser only when clicked. Text remains selectable, and equations/code can pan horizontally while the surrounding transcript owns vertical scrolling.

Validation: the final Debug build succeeded. An actual offline WebKit fixture verified bold text, headings, lists, a table, four math expressions including two fractions, integral/matrix markup and preserved code. Hostile HTML created no images, ran no injected script and retained no JavaScript links. No model allowance was used. This validates renderer behavior; a full live transcript walkthrough was not repeated in this pass.

Third-party licenses are bundled in ResponseRenderer-LICENSES.txt. Library behavior was checked against the primary documentation at https://marked.js.org/ and https://katex.org/docs/autorender .
