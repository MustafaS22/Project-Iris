# Automatic AI readiness and computer permissions

Iris discovers models automatically at launch and after AI settings or sign-in changes. Checks are debounced and cancelled when settings change. They do not send a test inference or consume a test response. A configured model can be used immediately even if catalogue discovery is unavailable; a blank selection discovers a chat model before the first request. A successful real response confirms inference. Reconnect remains available in Settings → AI.

Onboarding → Set the tone and Settings → Computer both expose Always allow computer actions. Existing installs default to review mode. Enabling the option lets supported app, playback, local-model and project tasks run automatically. File operations still require granted folders and can replace existing files. Project scripts run through Terminal with normal account access. macOS permissions remain required. Unsupported actions remain unsupported, and separately billed image generation always retains explicit review.

Automatic batches execute in order and recheck the permission before each action. Stop cancels remaining work; failure stops the batch without automatically retrying. Results and real files appear in chat. Changing permission does not execute previously queued actions on its own.
