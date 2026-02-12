# Paper Crumple Animation Design

## Goal
When a player taps **Draw next card**, the visible prompt card should feel like a physical piece of paper being tossed away. Instead of only shrinking, the paper now morphs into a crumpled paper ball before it exits.

## User Experience
1. Prompt card is visible with deck stack behind it.
2. On draw:
   - card starts moving up/right,
   - card rotates,
   - card rapidly morphs into a ball,
   - particles burst to emphasize motion.
3. Next prompt flips in once backend sync updates the prompt index.

## Implementation Approach
- Keep existing throw and flip animation controllers in `GameView`.
- Derive a `morphT` progress value from throw progress.
- During throw animation:
  - Fade out the `_PaperCard` as `morphT` increases.
  - Fade in `_PaperBall` with decreasing diameter.
- Add `_PaperBallPainter` to draw:
  - radial paper shading,
  - wrinkle strokes,
  - soft drop shadow.

This keeps the change UI-local without modifying pairing, prompt sync, or backend data schemas.

## Scope / Non-Goals
- No data model changes.
- No gameplay logic changes.
- No server/API changes.

## Validation
- Manual visual check in Flutter web app during paired gameplay.
- Ensure no regressions to:
  - next-prompt sync,
  - draw button disabled states,
  - existing particle effect.
