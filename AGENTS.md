# OpenHome project rules

Follow the user's global Codex workflow. Keep this public repository portable
and free of personal infrastructure, provider endpoints, credentials, sessions,
phone numbers, signing material, deployment domains, and captured artifacts.

## Development

- The application lives in `web/` and requires Node.js 22.13 or newer.
- Use the committed `web/package-lock.json`; install with `cd web && npm ci`.
- For every functional change, run from `web/`:
  `npm test`, `npm run lint`, and `npm run build:node`.
- For a meaningful UI change, also start the Node build, inspect runtime output,
  exercise the affected state in a browser, and capture a screenshot. Do not
  report completion for a UI change based only on a successful build.
- Do not commit `.env` files, local databases, provider responses, screenshots
  containing real data, or generated deployment configuration.
- Deployment must stop if tests, lint, or build fail.

## Architecture

- OpenHome is one product shell with independent modules such as OpenGate and
  OpenLiving. Reuse navigation, visual tokens, HTTP helpers, session crypto,
  storage ports, error mapping, and deployment adapters;
  never fork a second application stack for a new module.
- Keep UI and public APIs on stable domain models. Provider endpoints, raw
  response maps, signing/encryption inputs, cookies, client fingerprints, and
  version-specific action/property names stay behind provider adapters.
- Load compatibility values from the schema-versioned provider bundle. The
  optional private bundle service is an install/update input, never a proxy for
  ordinary user or device traffic.
- Preserve the deployment session-encryption key across releases. Treat a
  hostname change as an authentication migration because host-scoped HttpOnly
  cookies do not move with server state.
- Authentication challenges and device actions are budgeted side effects. Do
  not retry an unchanged failure; test offline first, use duplicate-action
  guards where applicable, and read state back after mutations.
- Share infrastructure only where semantics match. Module-specific sessions,
  adapters, capabilities, and domain state remain isolated behind typed ports.

## UI behavior

- Use one persistent top-level module switcher. Switching modules must be
  client-side, preserve mounted state, and must not reload the page. Do not
  repeat the active tab label as a redundant page title immediately below it.
- Keep controls compact, mobile-first, and information-dense. Prefer a narrow
  content column, medium action/program cards, short labels, and toasts for
  transient feedback; avoid explanatory copy when the control is self-evident.
- Show meaningful account, resource, and device names. Translate protocol
  enums and numeric states into user language; never expose labels such as
  `状态 1`, raw property names, or provider identifiers.
- Group power controls together and run/pause/schedule controls together.
  Destructive account logout requires an in-page confirmation. Preserve the
  established direct OpenGate action with its duplicate-request guard.
- For large program catalogs, show a useful common subset first and expose the
  complete categorized catalog through `更多`; do not hard-code a misleading
  four-item capability list.
- Scheduling is expressed as the user's desired start time. Convert it at the
  adapter boundary when an upstream protocol uses delay or completion time.
  Cancel scheduling must cancel only; do not silently power off or add another
  device mutation unless evidence and product requirements explicitly demand it.
- After meaningful UI changes, verify both modules, tab-state preservation,
  narrow and desktop layouts, loading/error/confirmation/toast states, browser
  console output, and the relevant real runtime path before completion.
