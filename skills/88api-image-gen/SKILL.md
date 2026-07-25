---
name: "88api-image-gen"
description: "Generate or edit images with the 88api.ai Token aggregation service via the gpt-image-2 Images API. Trigger for AI image generation, text-to-image, multi-reference image editing, batch or multi-worker generation, continuous generation, or saving generated images to disk."
version: "0.5.0"
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [image-generation, 88api, gpt-image-2, batch]
    category: productivity
    related_skills: []
---

# 88API-image-gen

Image generation and editing plugin from the 88api.ai Token aggregation service, usable from Codex, Claude Code, Cursor, and Hermes. It only calls `gpt-image-2` through `/v1/images/generations` and `/v1/images/edits`; no GPT text model permission is required. A single text-to-image task can opt into native Images API partial-image SSE previews.

## Script Location

The core script is `generate.mjs`, shipped once in this repository. Resolve it at runtime with this rule, in order:

1. Environment override: `88API_IMAGE_GEN_SCRIPT` (absolute path to `generate.mjs`)
2. Repository layout: `<SKILL_DIR>/../../plugins/88api-image-gen/scripts/generate.mjs` where `<SKILL_DIR>` is the directory containing this SKILL.md after symlink resolution
3. Legacy Codex plugin install: `$HOME/plugins/88api-image-gen/scripts/generate.mjs`

In shell form (POSIX):

```bash
SCRIPT="${88API_IMAGE_GEN_SCRIPT:-}"
if [ -z "$SCRIPT" ]; then
  SKILL_DIR="$(cd "$(dirname "$0")" && pwd -P)"   # resolve symlinks when running from ~/.claude/skills etc.
  SCRIPT="$SKILL_DIR/../../plugins/88api-image-gen/scripts/generate.mjs"
fi
[ -f "$SCRIPT" ] || SCRIPT="$HOME/plugins/88api-image-gen/scripts/generate.mjs"
node "$SCRIPT" --get-config
```

When the agent resolves the path itself (no `$0`), prefer: realpath of this skill directory, walk up to the repository root, then `plugins/88api-image-gen/scripts/generate.mjs`. All examples below use `node "$GEN"` with `GEN` set to the resolved script path.

## Entry Check

When helping a user install this plugin from its repository, perform this onboarding sequence in order:

1. Check `node --version`. Require Node.js 18 or newer; recommend Node.js 20+. Python is not required.
2. Install for the user's client (see repository README): Codex uses `codex plugin marketplace add DaYePython/88API-image-gen`; Claude Code uses `/plugin marketplace add DaYePython/88API-image-gen`; Cursor and Hermes use `install.sh` / `install.ps1` or a manual skill symlink.
3. Check the local resize backend: PowerShell/System.Drawing on Windows, built-in `sips` on macOS, or ImageMagick (`magick`/`convert`) on Linux/Unix.
4. Run the configuration check below.
5. If no key is configured, stop before generation and tell the user to visit `https://88api.ai/`, sign in, and create an **image-generation group key**. Then help the user save it locally with `--set-key`.

Every time this skill is triggered for generation, run:

```bash
node "$GEN" --get-config
```

The output is JSON with masked worker key previews. Never display a full API key.

- If `密钥状态` is `未配置` or `已配置密钥数` is `0`, do not attempt generation. Explain that an 88API image-generation group key is required, direct the user to `https://88api.ai/`, and save the key locally with:

```bash
node "$GEN" --set-key "<YOUR_88API_IMAGE_GROUP_KEY>"
```

`<YOUR_88API_IMAGE_GROUP_KEY>` is a placeholder and must be replaced with the real key created by the user at 88api.ai. Never write the real key into repository files, documentation, commits, logs, or the assistant response. Prefer letting the user enter it directly in their local terminal; if the user explicitly supplies it for configuration, do not echo it back.

- Optional API root (same config file as the key). Default is `https://88api.ai`. When the user needs a compatible reverse proxy, mirror, or self-hosted gateway, save a full `http://` or `https://` URL with:

```bash
node "$GEN" --set-api-root "https://your-gateway.example"
node "$GEN" --get-config
```

`--set-api-root` validation rules:

- Value must parse as a complete URL with `http:` or `https:` only
- Reject credentials in the URL, query strings, and hash fragments
- Trailing slashes are stripped; a path prefix is allowed, e.g. `https://host.example/v1-proxy`
- Endpoints become `{API根地址}/v1/images/generations` and `{API根地址}/v1/images/edits`
- `--get-config` reports `API根地址`, `API根地址来源` (`默认` or `自定义`), `文生图接口`, and `图生图接口`

Do not invent a custom API root. Only set it when the user explicitly provides a gateway URL.

- If the user wants multiple independent 88API workers, add more keys with:

```bash
node "$GEN" --add-worker-key "<ANOTHER_88API_IMAGE_GROUP_KEY>" --worker-name "<NAME>"
node "$GEN" --list-workers
```

Do not exceed 10 workers in this plugin. One key/worker is the recommended default. Configure multiple distinct keys only when the user needs several independent images generated concurrently. Warn that parallel image responses, reference-image buffers, and resizing can consume substantial memory. Low-spec computers should not use multiple workers; start with one and increase gradually only when memory allows.

Critical billing and stability warning:

- Low-spec computers must not run batch generation or multiple workers.
- If available memory is unknown, default to one worker and `--concurrency 1`.
- Before `--batch`, `--repeat`, `--batch-edit`, or `--workflow-batch-edit`, warn the user that local memory exhaustion can freeze the computer or crash the AI client.
- A local crash, disconnect, or failure to save the returned image does not cancel requests already submitted to 88API. Requests accepted or completed by the cloud may still be billed.
- Do not start a large batch until the user has seen this warning. For workflow batches, run `--dry-run` first and begin with `--limit 1 --concurrency 1`.

## Prompt Compiler and Orchestration

The model running this skill is the prompt planner. Prepare the final Image2 instruction from the current conversation without sending prompt planning to a separate external model.

Before a paid image request, turn the user's request and conversation context into one clear Image2 instruction:

- Preserve the user's intent, named people, brands, exact quoted text, numbers, required objects, and prohibitions.
- For reference images, state the role of each image in argument order: identity, product, composition, style, background, or other user-defined role.
- Add only useful composition, camera, lighting, material, color, background, and aspect details. Do not bloat a simple request.
- Never invent poster copy, logos, claims, prices, names, or product features.
- If the user says to use the prompt verbatim or not optimize it, pass the original prompt unchanged except for the script's required aspect suffix.
- Do not expose the internal compiled prompt unless the user asks to review it.

For an explicitly iterative request, the agent may orchestrate `generate -> inspect saved image -> edit`, using the saved result as the next reference. Each follow-up edit is a new paid request. Default to one generation only; perform at most one automatic corrective edit, and only when the user asked for iterative refinement. Never loop until "perfect" and never create extra variations without counting and disclosing them.

Transport policy:

- Default `--transport auto` and explicit `--transport images` both use the direct Images endpoints.
- Responses transport is disabled because image-generation group keys must not require a GPT text model.
- Real preview files are opt-in with `--preview` for one text-to-image task through `/v1/images/generations` SSE. Partial images may add image-output usage or charges, so enable them only when the user explicitly requests a live preview. Never enable preview files across a batch or edit task.
- An accepted or unknown Images request must not be silently retried after timeout, broken SSE, or a missing final image. The cloud task may still be billed.

## Worker Pool Rules

This plugin supports one plugin with many independent API workers.

- Each worker is one API key sharing the configured API root (`apiRoot` / `--set-api-root`, default `https://88api.ai`), model settings, and fixed 2K ratio matrix
- The worker pool is capped at 10 API workers
- Multiple workers increase memory usage; do not recommend them on low-spec computers
- Single tasks use one worker only
- Multiple independent tasks run in parallel across multiple workers
- The plugin does **not** infer prompt difficulty and does **not** split one image request into many workers
- The plugin only scales out when there are many independent tasks, such as:
  - `--count`
  - `--repeat`
  - `--batch`
  - `--batch-inline`
  - `--batch-edit`
  - `--edit --count N`

Important image-edit rule:

- `--edit --image a --image b --prompt ...` without `--batch-edit` is still one combined multi-reference edit request and must stay on one worker
- `--batch-edit --edit --image a --image b ...` means each source image is its own task and may be distributed across many workers

If a retryable worker error occurs before a task is accepted (`429`, `502`, `503`, `504`, `524`, rate limit, no available account, account pool busy, temporarily unavailable), that worker is cooled temporarily and queued work is retried on another healthy worker when possible. Errors marked `[NO-RETRY]` must never be resubmitted automatically.

If an auth/key error occurs, that worker is disabled for the current run. Other healthy workers continue.

## Display Rule

This plugin must immediately show every successful saved image in the conversation with an absolute-path Markdown image tag such as `![result](/absolute/path.png)`.

Apply this to all successful outputs from text-to-image, edit, `--count`, `--repeat`, batch, and batch edit runs. If multiple images succeed, show all successful images in the same reply and separately report any failed items. Include the worker label in the text summary when useful for troubleshooting.

Special case for large workflow batch-edit runs:

- Do not dump hundreds of images into one reply
- Show the summary, failures, and only a small sample such as the first 8 successful images or one sample per scene
- The full result set stays on disk under the generated output folder

## Generate

For clear text-to-image requests, do not ask for confirmation:

```bash
node "$GEN" --prompt "<PROMPT>"
```

Generation requests are fixed to the 2K preset matrix. Do not offer 1K or 4K choices. If the user asks for 1K, 4K, or an exact pixel size, map the request to the nearest supported fixed aspect preset and tell them: `图像请求规格与实际计费以 88api.ai 控制台为准。`

Pass only `--ratio` or `--aspect` when the user asks for a shape. Do not use `--size` for normal generation or edit requests.

```bash
node "$GEN" --prompt "<PROMPT>" --aspect 16:9
```

Supported aspects are fixed to `1:1`, `3:2`, `2:3`, `4:3`, `3:4`, `16:9`, `9:16`, `2:1`, `1:2`, `7:4`, and `4:7`. Aliases are `square=1:1`, `landscape=4:3`, and `portrait=3:4`.

The ratios `5:4`, `4:5`, `3:1`, and `1:3` are disabled in this plugin because repeated upstream compatibility tests returned upstream `502` for them. Do not request them, and do not re-enable them unless new real tests prove they are stable.

The upstream service may return a near-aspect image with non-exact pixels. The script center-crops/resizes the saved PNG to the requested `WIDTHxHEIGHT` and reports `resized from <original>`. It uses System.Drawing on Windows, the built-in `sips` command on macOS, and ImageMagick (`magick` or `convert`) on Linux/Unix. Use `--no-resize` when testing the true upstream raster.

For same-prompt multi-image requests, use `--count 1..9`. For longer continuous runs, use `--repeat 1..50`. Each image is a separate paid Images API request and can be distributed to different workers:

```bash
node "$GEN" --prompt "一只钓鱼的小猫" --count 2 --concurrency 1 --aspect 16:9
node "$GEN" --prompt "一只钓鱼的小猫" --repeat 2 --concurrency 1 --adaptive
```

Single text-to-image tasks can opt into real SSE previews:

```bash
node "$GEN" --prompt "<PROMPT>" --aspect 16:9 --preview
```

## Batch Generate

Before running batch generation, apply the critical billing and stability warning above. On low-spec hardware, do not run it; process prompts one at a time instead.

Use batch mode for multiple different prompts:

```bash
node "$GEN" --batch-inline "<PROMPT_1>" "<PROMPT_2>" --concurrency 1
node "$GEN" --batch "<FILE.json>" --concurrency 1
```

If batch config is missing, ask for ratio/aspect and concurrency, then save it:

```bash
node "$GEN" --set-batch-mode --ratio 4:3 --concurrency 1
```

## Image Edit and Multi-Reference Edit

For image-to-image, pass `--edit` with one or more `--image` flags:

```bash
node "$GEN" --edit --image "<PATH_1>" --prompt "<EDIT_INSTRUCTION>" --aspect 9:16
```

For multi-reference image-to-image, pass multiple `--image` flags. A single combined task uploads ordered multipart `image[]` files:

```bash
node "$GEN" --edit --image "<PATH_1>" --image "<PATH_2>" --prompt "<EDIT_INSTRUCTION>" --aspect 9:16
```

To force per-source batch behavior instead of one combined multi-reference request, opt in explicitly:

```bash
node "$GEN" --batch-edit --edit --image "<PATH_1>" --image "<PATH_2>" --prompt "<EDIT_INSTRUCTION>" --concurrency 1
```

`--transport auto` and `--transport images` are accepted. Legacy Responses edit routes are rejected. Never automatically resend a paid request whose state is accepted or unknown.

## Generic Workflow Batch Edit

For real production tasks, prefer generic `--workflow-batch-edit` over any hardcoded product type:

Low-spec computers must not run this workflow directly. Always warn that a local crash does not cancel cloud-side requests and accepted requests may still be billed, then start with `--limit 1 --concurrency 1 --dry-run`.

```bash
node "$GEN" --workflow-batch-edit --fixed-ref "<固定参考图.png>" --item-dir "<变量图目录>" --template-inline "保持主体特征，生成 9:16 展示图" --limit 1 --aspect 9:16 --concurrency 1 --dry-run
```

- `--fixed-ref` is repeatable and carries fixed persona, brand, scene, style, or product baseline references.
- `--item-dir` is the directory of variable item images (products, clothing, props, packaging, furniture, etc.).
- `--templates` or `--template-inline` decides which scenes each variable item gets.
- Each variable item is one task group; each template is one independent paid Images edit image.
- Reference order is fixed: all fixed refs first, the current variable item last.
- The plugin does not assume product type; product semantics must come from user templates and reference images.

Template JSON supports an array or `{ "templates": [...] }`:

```json
{
  "templates": [
    {
      "key": "catalog_scene",
      "label": "Catalog Scene",
      "prompt": "Use the variable item as the main reference and create a clean catalog-style scene. Do not assume product category."
    },
    {
      "key": "lifestyle_scene",
      "label": "Lifestyle Scene",
      "prompt": "Place the variable item naturally into a lifestyle environment based on the fixed references."
    }
  ]
}
```

Production experience is built into the workflow:

- Automatic resume: existing valid PNGs in the same output directory are skipped.
- Automatic gap repair: after the main batch, missing outputs are scanned and re-run at low concurrency.
- Full reports: `manifest.json`, `summary.csv`, `failures.json`, `sessions.json`.
- Failure classification: `timeout_524`, `no_image_result`, `network`, `content_policy`, `auth`, `retryable`, `fatal`.
- Task groups bind to workers by default for stability; scenes of the same variable item stay on a consistent schedule when possible.

Remove `--dry-run` after confirming the task count. The workflow supports resume, automatic gap repair, and writes:

- `manifest.json`
- `summary.csv`
- `failures.json`
- `sessions.json`

Built-in nail try-on preset:

```bash
node "$GEN" --workflow-batch-edit --fixed-ref "<人物参考图.png>" --item-dir "<产品图目录>" --preset nail-tryon --limit 1 --concurrency 1 --aspect 9:16 --dry-run
```

## Nail Try-On Preset / Legacy Stress Test

The old `--nail-stress-test` command is kept as a compatibility shortcut for the successful nail try-on production test. For new production tasks, prefer `--workflow-batch-edit` with a custom template or `--preset nail-tryon`.

```bash
node "$GEN" --nail-stress-test --persona "<人物参考图.png>" --product-dir "<产品图目录>" --limit 1 --concurrency 1 --dry-run
```

Compatibility rules for this command:

- Fixed to `9:16` only
- Uses exactly two reference images per task, in this order:
  - reference 1: persona image
  - reference 2: one nail product image
- Selects the first `N` product images by natural numeric sort
- Generates 4 independent scene prompts per product:
  - hands closeup
  - hand half face
  - half body pose
  - full body scene
- Each scene is one independent paid Images edit request and may go to a different healthy worker
- The persona image is loaded once; product images are loaded on demand task by task
- Output root defaults to `~/Pictures/88api-image-gen/nail-stress-test_<timestamp>`
- Per-product output files are fixed to `01_hands_closeup.png`, `02_hand_half_face.png`, `03_half_body_pose.png`, `04_full_body_scene.png`
- The root output folder also includes `manifest.json`, `summary.csv`, `failures.json`, and `sessions.json` in the generic workflow path

Equivalent generic workflow form:

```bash
node "$GEN" --workflow-batch-edit --fixed-ref "<人物参考图.png>" --item-dir "<产品图目录>" --preset nail-tryon --limit 1 --concurrency 1 --aspect 9:16 --dry-run
```

Use `--dry-run` first to verify product selection and total task count without calling 88API.

## API Contract

- API root: configurable with `--set-api-root <http(s) URL>`; default `https://88api.ai`; stored as `apiRoot` in `~/.agents/88api-image-gen-config.json` (legacy `~/.codex/88api-image-gen-config.json` is migrated automatically on first load)
- Text-to-image: `POST {API_ROOT}/v1/images/generations`
- Image edit: `POST {API_ROOT}/v1/images/edits`
- Model: always `gpt-image-2`; GPT text-model permission is not required
- Request size policy: always use the fixed 2K preset matrix and the supported aspect list above; do not request 1K, 4K, disabled ratios, or arbitrary `--size`
- Auth: `Authorization: Bearer <88API Key>`
- Images generation body: JSON with `model`, `prompt`, `size`, and `n:1`
- Preview generation adds `stream:true` and `partial_images:1`, consumes `image_generation.partial_image` SSE incrementally, and saves the final image
- Images edit body: multipart form data with `model`, `prompt`, `size`, `n`, and ordered `image[]` files
- Images result parsing: read `data[].b64_json`, with URL download fallback when the gateway returns `data[].url`
- Safety: never cross-fallback or automatically retry after an accepted/unknown paid request marked `[NO-RETRY]`
- Worker routing rule: single task = single worker; multiple independent tasks = many workers when available
- Workflow batch edit: generic fixed refs + variable item ref + user templates. Do not assume product type.
- Workflow reliability: resume existing PNG outputs, auto repair missing outputs, and write `manifest.json`, `summary.csv`, `failures.json`, and `sessions.json`.

## Verification

After changing the script or 88API contract, run:

```bash
node --check "$GEN"
node "$GEN" --help
node "$GEN" --get-config
node "$GEN" --list-workers
node "$GEN" --resolve-size --aspect 9:16
node "$GEN" --self-test-adaptive
node "$GEN" --self-test-images-api
node "$GEN" --self-test-image-stream
node "$GEN" --self-test-workflow
node "$GEN" --workflow-batch-edit --fixed-ref "<人物参考图.png>" --item-dir "<产品图目录>" --preset nail-tryon --limit 1 --concurrency 1 --aspect 9:16 --dry-run
node "$GEN" --nail-stress-test --persona "<人物参考图.png>" --product-dir "<产品图目录>" --limit 1 --concurrency 1 --dry-run
```

When real generation or edit requests succeed, always show the successful saved images in the conversation immediately with absolute-path Markdown image tags.

## Limits

- Quick same-prompt generation: 1 to 9 images
- Continuous generation: `--repeat 1..50`
- Request quality: fixed 2K
- Edit variations: 1 to 4 images
- Batch prompts: up to 20
- Batch edit source images: up to 10
- Workflow batch edit default limit: first 100 item images unless `--limit` is provided
- Workflow repair passes: default 2, configurable with `--repair-passes 0..5` or disabled with `--no-repair`
- Worker count: 1 to 10
- Worker pool concurrency: 1 to 10
- Generation timeout: 180 seconds
- Edit timeout: 180 seconds
