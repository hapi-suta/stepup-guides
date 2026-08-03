-- Sample customer-support tickets for Project 1.
-- Run once against labdb to create and populate the table.

CREATE TABLE IF NOT EXISTS support_tickets (
    id          SERIAL PRIMARY KEY,
    subject     TEXT NOT NULL,
    body        TEXT,
    category    TEXT,
    created_at  TIMESTAMPTZ DEFAULT now()
);

INSERT INTO support_tickets (subject, body, category) VALUES
    ('Cannot log in',              'Password reset link never arrives',      'auth'),
    ('Login loop after reset',     'Keeps redirecting to sign in',           'auth'),
    ('Invoice is wrong',           'Charged twice this month',               'billing'),
    ('Refund not received',        'Waiting 10 days for refund',             'billing'),
    ('Refund status?',             'Where is my money',                      'billing'),
    ('App crashes on upload',      'Crash when I attach a PDF',              'bug'),
    ('Export button does nothing', 'No download happens',                    'bug'),
    ('How do I add a user',        'Need to invite a teammate',              NULL),
    ('Feature request: dark mode', 'Please add dark mode',                   'feature'),
    ('Slow dashboard',             'Takes 30s to load',                      'performance');
