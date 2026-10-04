import { config } from '../config.js';

export type Verdict = { approved: true } | { approved: false; reason: string };

// Minimal local fallback used when no moderation provider is configured.
const BLOCKLIST = [/\bkill yourself\b/i, /\bkys\b/i, /\bn[i1]gg(er|a)\b/i, /\bf[a@]gg?ot\b/i];

function localText(text: string): Verdict {
  return BLOCKLIST.some((re) => re.test(text)) ? { approved: false, reason: 'local_blocklist' } : { approved: true };
}

/** Screens text and (optionally) an image URL before a drop or echo goes live (spec F-05). */
export async function moderate(input: { text?: string; imageUrl?: string }): Promise<Verdict> {
  const text = input.text?.trim() ?? '';
  if (!config.OPENAI_API_KEY) return text ? localText(text) : { approved: true };

  const parts: unknown[] = [];
  if (text) parts.push({ type: 'text', text });
  if (input.imageUrl) parts.push({ type: 'image_url', image_url: { url: input.imageUrl } });
  if (parts.length === 0) return { approved: true };

  const res = await fetch('https://api.openai.com/v1/moderations', {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${config.OPENAI_API_KEY}` },
    body: JSON.stringify({ model: 'omni-moderation-latest', input: parts }),
  });
  if (!res.ok) throw new Error(`moderation failed: ${res.status}`);
  const body = (await res.json()) as { results: { flagged: boolean; categories: Record<string, boolean> }[] };
  const flagged = body.results.find((r) => r.flagged);
  if (!flagged) return { approved: true };
  const reason = Object.entries(flagged.categories)
    .filter(([, v]) => v)
    .map(([k]) => k)
    .join(',');
  return { approved: false, reason };
}
