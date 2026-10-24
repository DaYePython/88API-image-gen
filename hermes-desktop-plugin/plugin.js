/**
 * 88API-image-gen desktop panel for the Hermes desktop app.
 * Save target: ~/.hermes/desktop-plugins/88api-image-gen/plugin.js
 *
 * The desktop-plugin sandbox can only import @hermes/plugin-sdk, react, and
 * react/jsx-runtime, so this panel cannot spawn the generate.mjs CLI itself.
 * Instead it builds the exact command line and lets the user copy it into a
 * Hermes session, where the agent (via the 88api-image-gen skill) runs it.
 *
 * Plain ESM, loaded uncompiled — UI is jsx() calls, not JSX syntax.
 */

import { Button, CopyButton, Input, Select, SelectContent, SelectItem, SelectTrigger, SelectValue, Textarea, haptic, host } from '@hermes/plugin-sdk'
import { useState } from 'react'
import { jsx, jsxs } from 'react/jsx-runtime'

const ASPECTS = ['1:1', '3:2', '2:3', '4:3', '3:4', '16:9', '9:16', '2:1', '1:2', '7:4', '4:7']

const SCRIPT_HINT = 'plugins/88api-image-gen/scripts/generate.mjs'

function buildCommand({ mode, prompt, aspect, preview, count, images, model }) {
  const parts = ['node', `"$GEN"`]
  if (mode === 'edit') {
    parts.push('--edit')
    for (const imagePath of images) {
      const trimmed = imagePath.trim()
      if (trimmed) parts.push('--image', `"${trimmed}"`)
    }
  }
  parts.push('--prompt', `"${prompt.replace(/"/g, '\\"')}"`)
  const trimmedModel = String(model || '').trim()
  if (trimmedModel) parts.push('--model', `"${trimmedModel.replace(/"/g, '\\"')}"`)
  if (aspect) parts.push('--aspect', aspect)
  if (mode === 'generate' && preview) parts.push('--preview')
  if (mode === 'generate' && count > 1) parts.push('--count', String(count), '--concurrency', '1')
  return parts.join(' ')
}

function Field({ label, children }) {
  return jsxs('label', {
    className: 'flex flex-col gap-1',
    children: [
      jsx('span', { className: 'text-xs text-(--ui-text-tertiary)', children: label }),
      children
    ]
  })
}

function ImageGenPane() {
  const [mode, setMode] = useState('generate')
  const [prompt, setPrompt] = useState('')
  const [model, setModel] = useState('')
  const [aspect, setAspect] = useState('1:1')
  const [preview, setPreview] = useState(false)
  const [count, setCount] = useState(1)
  const [imagesText, setImagesText] = useState('')

  const images = imagesText.split('\n')
  const command = buildCommand({ mode, prompt: prompt || '<PROMPT>', aspect, preview, count, images, model })

  return jsxs('div', {
    className: 'flex h-full flex-col gap-3 overflow-auto p-3 text-sm',
    children: [
      jsxs('div', {
        className: 'flex flex-col gap-0.5',
        children: [
          jsx('div', { className: 'font-medium', children: '88API Image Gen' }),
          jsx('div', {
            className: 'text-xs text-(--ui-text-tertiary)',
            children: 'Build a generate.mjs command, copy it, and paste it into your Hermes session. The agent runs it via the 88api-image-gen skill.'
          })
        ]
      }),

      jsxs(Field, {
        label: 'Mode',
        children: [
          jsxs(Select, {
            value: mode,
            onValueChange: setMode,
            children: [
              jsx(SelectTrigger, { children: jsx(SelectValue, {}) }),
              jsxs(SelectContent, {
                children: [
                  jsx(SelectItem, { value: 'generate', children: 'Text to image' }),
                  jsx(SelectItem, { value: 'edit', children: 'Edit with reference image(s)' })
                ]
              })
            ]
          })
        ]
      }),

      mode === 'edit' && jsx(Field, {
        label: 'Reference image paths (one per line, max 10)',
        children: jsx(Textarea, {
          value: imagesText,
          onChange: (event) => setImagesText(event.target.value),
          rows: 3,
          placeholder: '/absolute/path/to/reference.png'
        })
      }),

      jsx(Field, {
        label: 'Prompt',
        children: jsx(Textarea, {
          value: prompt,
          onChange: (event) => setPrompt(event.target.value),
          rows: 4,
          placeholder: 'Describe the image you want...'
        })
      }),

      jsx(Field, {
        label: 'Model (optional)',
        children: jsx(Input, {
          value: model,
          onChange: (event) => setModel(event.target.value),
          placeholder: 'gpt-image-2 (default), gpt-image-2.5-flare, gpt-image-2.5-sunburst...'
        })
      }),

      jsxs(Field, {
        label: 'Aspect',
        children: [
          jsxs(Select, {
            value: aspect,
            onValueChange: setAspect,
            children: [
              jsx(SelectTrigger, { children: jsx(SelectValue, {}) }),
              jsx(SelectContent, {
                children: ASPECTS.map((value) => jsx(SelectItem, { value, children: value }, value))
              })
            ]
          })
        ]
      }),

      mode === 'generate' && jsxs('div', {
        className: 'flex items-center gap-3',
        children: [
          jsxs('label', {
            className: 'flex items-center gap-1.5 text-xs',
            children: [
              jsx('input', {
                type: 'checkbox',
                checked: preview,
                onChange: (event) => setPreview(event.target.checked)
              }),
              'SSE preview (may add cost)'
            ]
          }),
          jsxs('label', {
            className: 'flex items-center gap-1.5 text-xs',
            children: [
              'Count',
              jsx(Input, {
                className: 'w-14',
                type: 'number',
                min: 1,
                max: 9,
                value: String(count),
                onChange: (event) => setCount(Math.max(1, Math.min(9, Number(event.target.value) || 1)))
              })
            ]
          })
        ]
      }),

      jsxs('div', {
        className: 'flex flex-col gap-1.5 rounded-md border border-(--ui-stroke-secondary) p-2',
        children: [
          jsx('div', { className: 'text-xs text-(--ui-text-tertiary)', children: 'Command (GEN = resolved generate.mjs path)' }),
          jsx('code', {
            className: 'block whitespace-pre-wrap break-all text-xs text-(--ui-text-secondary)',
            children: command
          }),
          jsxs('div', {
            className: 'flex items-center justify-between gap-2',
            children: [
              jsx('span', { className: 'text-[0.6875rem] text-(--ui-text-quaternary)', children: `script: ${SCRIPT_HINT}` }),
              jsx(CopyButton, { value: command })
            ]
          })
        ]
      }),

      jsx(Button, {
        variant: 'secondary',
        onClick: () => {
          haptic('tap')
          host.notify({ kind: 'info', message: 'Paste the copied command into your Hermes session to run it.' })
        },
        children: 'How to run'
      })
    ]
  })
}

export default {
  id: '88api-image-gen',
  name: '88API Image Gen',
  register(ctx) {
    ctx.register({
      id: 'pane',
      area: 'panes',
      title: '88API Image Gen',
      data: { placement: 'right', width: '280px' },
      render: () => jsx(ImageGenPane, {})
    })
  }
}
