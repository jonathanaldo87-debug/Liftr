-- Repairs the discipline emoji, and makes them immune to it happening again.
--
-- 009 shipped the emoji as literal UTF-8 characters. The file was correct, but
-- whatever executed it decoded those bytes as Windows-1252, so the barbell
-- (F0 9F 8F 8B EF B8 8F) landed in the table as the mojibake "ð<9f><8f>‹ï¸<8f>".
-- The chips and onboarding cards render that garbage instead of an icon.
--
-- The real fix is not to re-paste the emoji: the same client would mangle them
-- again. This file is PURE ASCII and uses Postgres unicode escapes (U&'...'),
-- which no client encoding can corrupt. Any future emoji added to this table
-- should be written the same way.
--
--   U&'\+01F3CB'  = U+1F3CB  barbell
--   U&'\+00FE0F'  = U+FE0F   variation selector-16 (renders it as an emoji)
--   U&'\+01F3C3'  = U+1F3C3  runner
--
-- ADDITIVE: only rewrites the emoji column. Safe to re-run.

BEGIN;

UPDATE disciplines
SET emoji = U&'\+01F3CB\+00FE0F'
WHERE discipline_key = 'gym';

UPDATE disciplines
SET emoji = U&'\+01F3C3'
WHERE discipline_key = 'running';

COMMIT;

-- Expect: gym -> 1f3cb,fe0f and running -> 1f3c3.
-- If a row still shows a run of 00f0/0178/... codepoints, the emoji were
-- mangled again and the client encoding is still wrong.
SELECT
  discipline_key,
  emoji,
  (SELECT string_agg(lpad(to_hex(ord(c)), 4, '0'), ',')
     FROM unnest(string_to_array(emoji, NULL)) AS c) AS codepoints
FROM disciplines
ORDER BY sort_order;
