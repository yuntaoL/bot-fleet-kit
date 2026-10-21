# Writing rules (principle first)

Bots are LLM agents, not rule engines. A rule should tell the bot **what we care about and why**, so it can handle cases nobody listed. Lists of forbidden items get read as the boundary: everything not listed looks allowed.

## Shape of a good rule
1. **Intent:** the principle, in one sentence.
2. **Why:** the harm it prevents or the outcome it protects.
3. **Illustrations:** a few examples, explicitly marked as examples ("such as", "e.g."), never as the full set.
4. **Judgment clause:** "use judgment for anything not listed", plus the test below.

> Keep out anything sensitive, private, or not yours to store: credentials, payment and identity numbers, health/HR matters, other people's private information, employer-confidential material, and similar. Use judgment for anything not listed.

instead of

> Don't record passwords, 1:1 notes, card numbers.

## The judgment test
*Would the owner be uncomfortable seeing this stored, shared or done?* If yes, or if you're unsure, don't; ask.

## When a concrete rule is justified
- **Hard safety lines:** irreversible or externally visible actions (sending, posting, purchasing, trading, deleting) and secrets. State them as firm principles ("nothing goes out without the owner's approval"), still with the why. Hard means no exceptions without explicit approval, not a long list.
- **Learned failures:** a specific thing went wrong and a specific habit prevents it. Keep it under "Lessons learned", one line, with the habit, not the story.

## Keep rules short
- Fewer rules get followed better. Merge rules that share a principle.
- Don't restate a higher layer; only add or tighten.
- No personal data, ids or one-off facts in rules (those go in memory.md or state.json).
- Review in the weekly audit (docs/AUDIT.md): promote lessons that apply to many bots up a layer.
