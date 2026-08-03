-- Seed users, a few documents/chunks, so the app answers something on day one.
-- Tokens and the OIDC email mapping are plain here for the demo ONLY.
-- In production, tokens are hashed and users come entirely from the IdP.

-- Two demo users: one plain 'user', one 'admin'. Both can log in via SSO
-- (matched on email) or call the API directly with their bearer token.
INSERT INTO app_users (username, email, api_token, role, clearance) VALUES
    ('alice',  'alice@example.com', 'token-alice', 'user',  2),
    ('admin',  'admin@example.com', 'token-admin', 'admin', 4)
ON CONFLICT (username) DO UPDATE
    SET email = EXCLUDED.email,
        api_token = EXCLUDED.api_token,
        role = EXCLUDED.role,
        clearance = EXCLUDED.clearance;

-- A couple of starter documents so /ask returns grounded content immediately.
INSERT INTO documents (title, source, access_level) VALUES
    ('Expense Policy',   'expense-policy.txt', 1),
    ('Incident Response','incident-response.txt', 2)
ON CONFLICT DO NOTHING;

-- Chunks tied to those documents. access_level gates who can retrieve them.
INSERT INTO chunks (doc_id, chunk_text, source, access_level)
SELECT d.id,
       'Employees may expense meals up to 40 dollars per day while travelling. Receipts are required for any single item over 25 dollars.',
       'expense-policy.txt', 1
FROM documents d WHERE d.source = 'expense-policy.txt'
AND NOT EXISTS (SELECT 1 FROM chunks c WHERE c.source = 'expense-policy.txt');

INSERT INTO chunks (doc_id, chunk_text, source, access_level)
SELECT d.id,
       'On a suspected breach, page the on-call security lead within 15 minutes, isolate the affected host, and open an incident channel. Do not power off the host - preserve volatile memory for forensics.',
       'incident-response.txt', 2
FROM documents d WHERE d.source = 'incident-response.txt'
AND NOT EXISTS (SELECT 1 FROM chunks c WHERE c.source = 'incident-response.txt');
