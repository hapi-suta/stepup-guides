-- Seed demo users with different clearance levels.
-- clearance is the maximum chunk access_level the user may retrieve:
--   1 public, 2 internal, 3 confidential, 4 restricted
-- Tokens are plain for the demo only; in production use hashed secrets.

INSERT INTO app_users (username, api_token, clearance) VALUES
    ('intern',   'token-intern',   1),
    ('employee', 'token-employee', 2),
    ('secops',   'token-secops',   3),
    ('board',    'token-board',    4)
ON CONFLICT (username) DO UPDATE
    SET clearance = EXCLUDED.clearance,
        api_token = EXCLUDED.api_token;
