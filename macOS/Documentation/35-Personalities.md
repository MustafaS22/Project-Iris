# Iris personalities

Choose **Settings → Personality**, use the character name beneath Iris's avatar in the main chat, or choose a personality during onboarding's About you step. Choices save on this Mac and apply to subsequent requests, including existing conversations.

| Personality | Character |
| --- | --- |
| Companion | Relaxed, warm, quietly encouraging, with a little understated wit |
| Witty | Quick thinking and dry humour; banter aimed at the situation, never the user |
| Composed | A polished, unflappable personal aide with understated charm |
| Spark | Playful optimism, small experiments and momentum without relentless cheerleading |
| Sage | Curiosity, patient explanations and useful questions without turning every answer into a lesson |
| Direct | Candid, practical and concise, with respectful pushback when useful |

The chooser includes three locally written comparison situations: getting started, a small win, and something going wrong. Switching personalities or situations does not call a model. Examples are labeled as previews, not live generated answers. **Hear sample** uses the configured voice provider and its normal usage, with existing preview caching. Preview audio stops when leaving the preview, changing the personality or changing the scenario. Switching styles alone does not interrupt an unrelated spoken answer.

Personality instructions are supplied to both local and cloud model requests. Desktop, notch and floating chat share the normal request pipeline; Studio, notebooks and Create also receive the chosen character. Source grounding, exact output formats, requested writing tone, action permissions and truthful execution reports retain priority. Personality affects surrounding conversation; it does not rewrite a requested document into jokes or loosen source requirements. All personalities remain Iris, an AI assistant, without invented human memories or claims of human feelings. They adapt their tone for serious or upsetting situations.

The main chat greeting changes with the selected character. **Match voice delivery to personality** keeps the selected voice while choosing a compatible Gemini delivery style: Warm for Companion, Calm for Composed/Sage, Focused for Direct and Natural for Witty/Spark. VoiceBox and Mac voices keep their existing delivery. Turning matching off restores the user's configured Gemini style. Existing preferences with no personality selection keep their previous speech style; no voice, account, permission or theme setting is reset.

Stable string IDs persist in optional preference fields. Missing or unknown IDs fall back to Companion, preserving older state files. A personality change affects the next model request; an answer already being generated retains its captured style.

## Validation
The macOS Debug build succeeded and all 174 core tests passed. Four new tests cover legacy/unknown preference handling, persistence and voice opt-out, distinct bounded preview examples, and personality instruction constraints. The chooser was rendered and visually inspected at wide and narrow sizes using synthetic local state. No live model inference or speech generation was used in validation; exact model adherence and provider voice quality remain unverified.
