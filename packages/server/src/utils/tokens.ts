const CHARS_PER_TOKEN = 4;

export function estimateTokens(text: string): number {
  return Math.ceil(text.length / CHARS_PER_TOKEN);
}

export function truncateToTokenBudget(
  text: string,
  budget: number,
): { text: string; truncated: boolean } {
  const maxChars = budget * CHARS_PER_TOKEN;
  if (text.length <= maxChars) {
    return { text, truncated: false };
  }

  const totalEstimate = estimateTokens(text);
  const truncated = text.slice(0, maxChars);
  const lastNewline = truncated.lastIndexOf("\n");
  const cleanCut = lastNewline > maxChars * 0.8 ? truncated.slice(0, lastNewline) : truncated;

  return {
    text:
      cleanCut +
      `\n\n---\n*Truncated — showing ~${budget} of ~${totalEstimate} tokens. Narrow your query with filter, depth, or lineRange.*`,
    truncated: true,
  };
}
