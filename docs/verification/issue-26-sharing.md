# Automatic plain-task sharing

The installed **Add to tsk** Share extension accepts text and URLs through the
native system share sheet. Selecting it saves one plain task immediately and
completes the extension request after durable local commit. There is no editor,
confirmation form, annotation, project, tag, priority or date control. Multiline
text and URLs form the full task description, joined by a blank line when there
are multiple distinct input items. A provider offering a URL and text uses its
URL once. File attachments remain unsupported.

Core owns sharedDescription(from:) and captureSharedTask. The latter uses the
ordinary task creation, mutation lease and post-commit effects. Storage or input
failure cancels the system request and never acknowledges a saved task. Local
save does not wait for synchronization; the app handles later convergence.

The extension retains the common participant-directory policy: shared storage
must have been initialized by opening tsk, and extensions cannot migrate private
data or fall back to another replica. It has the same App Group, embedded target
and per-target provisioning requirements as before. No credentials or new
storage location are introduced.

TskShareFixture is a test source app with no task-storage access. The permanent
installed-extension test initializes the main app, then shares text, a URL, and
both through the real activity sheet. It checks the native host completion,
absence of an editor, the exact description in tsk and persistent row identity
after relaunch. Core/Native coverage checks plain fields, actual item providers,
URL representation deduplication, rejected files, durable reopen and actual
storage-failure behavior. Optional sync/reference-client integration has its
own environment requirements and must not be inferred from a generic build.

Current verification is recorded on the pull request; source/build/local
simulator results do not replace final canonical both-family UI coverage or
physical-device verification.
