# findings — FlyBy for Mail

Append-only log. Newest first.

## 2026-11-19 — Mail ignores an extension that does not declare its capabilities

- Symptom: `pluginkit -m -p com.apple.email.extension` listed the signed extension (even elected with `+`), but Mail ▸ Settings ▸
  Extensions said "No Extensions".
- Cause: the Info.plist had no `NSExtension ▸ NSExtensionAttributes ▸ MEExtensionCapabilities` array. Xcode's Mail Extension template
  (`Mail Extension.xctemplate/TemplateInfo.plist` in Xcode.app) puts `MEComposeSessionHandler` (and the other chosen handlers) there;
  `MEComposeSession` (icon = SF Symbol name, tooltip) sits in the same `NSExtensionAttributes`.
- Lesson: pluginkit registration is not proof that Mail lists the extension; check Mail's Extensions pane.

## 2026-11-19 — Mail extension must be ticked inside Mail; compose icon

- `pluginkit -e use` ("+") is macOS's own election, **not** the checkbox in Mail ▸ Settings ▸ Extensions. Mail's log said
  `Extension app.legba.flybymail.extension is userEnabled: Not Enabled and optedIn: YES` until the user ticked the box
  (`/usr/bin/log show --predicate 'process == "Mail" AND eventMessage CONTAINS[c] "flyby"'`; in zsh `log` is a builtin, use the full path).
- Once ticked: compose begin, the toolbar button, and the picker popover all worked (operator screenshot). Mail shows the permission text
  "Email Contents: can read sensitive information from emails including the message subject and recipients. This applies to all outgoing messages."
- `MEComposeIcon` = `airplane.departure` (SF Symbol name) was ignored (generic puzzle-piece icon). Replaced by the brand airplane as a template image:
  `scripts/make-compose-icon.swift` renders `Resources/icon/flyby-icon.svg` (copy of the FlyBy brand plane) to `FlyByTemplate.png`/`@2x.png`,
  copied into the appex `Resources`; `MEComposeIcon` = `FlyByTemplate`. Not yet confirmed visually.
