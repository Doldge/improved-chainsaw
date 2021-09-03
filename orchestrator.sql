DROP SCHEMA IF EXISTS invoice CASCADE;
CREATE SCHEMA invoice;

/* Roll charges & Credit Notes together.
 * Then link the invoice.invoice(id) <= Payment.
 * (Pay for the amount outstanding on the invoice).
 */
DROP TABLE IF EXISTS invoice.invoice;
CREATE TABLE invoice.invoice (
    id INTEGER GENERATED ALWAYS AS IDENTITY,
    memberid INTEGER,
    PRIMARY KEY (id)
);


DROP TABLE IF EXISTS invoice.invoice_component;
CREATE TABLE invoice.invoice_component (
    id INTEGER GENERATED ALWAYS AS IDENTITY,
    invoice_id INTEGER NOT NULL,
    posting_id INTEGER NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (invoice_id)
        REFERENCES invoice.invoice (id)
        ON DELETE CASCADE,
    FOREIGN KEY (posting_id)
        REFERENCES accounting.posting_credit(id)
        ON DELETE CASCADE,
        CHECK (
            accounting_view.is_valid_charge_journal(posting_id)
            OR accounting_view.is_valid_credit_note_journal(posting_id)
            OR accounting_view.is_valid_transfer_journal(posting_id)
        )
);

/* Roll Payments & Debit Notes together.
 * Then link the invoice.payment(id) => To an invoice.
 */
CREATE TABLE invoice.payment (
    id INTEGER GENERATED ALWAYS AS IDENTITY,
    memberid INTEGER NOT NULL,
    PRIMARY KEY (id)
);

CREATE TABLE invoice.payment_component (
    id INTEGER GENERATED ALWAYS AS IDENTITY,
    payment_id INTEGER NOT NULL,
    posting_id INTEGER NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (payment_id)
        REFERENCES invoice.payment (id)
        ON DELETE CASCADE,
    FOREIGN KEY (posting_id)
        REFERENCES accounting.posting_credit(id)
        ON DELETE CASCADE,
        CHECK (
            accounting_view.is_valid_payment_journal(posting_id)
            OR accounting_view.is_valid_debit_note_journal(posting_id)
            OR accounting_view.is_valid_transfer_journal(posting_id)
        )
);


/* The accounting_view FK means that credit/debit notes do not
 * work with these columns.
 * Add a CHECK here to ensure you can't over-pay an invoice.
 */
DROP TABLE IF EXISTS invoice.invoice_payment;
CREATE TABLE invoice.invoice_payment(
    invoice_component_id INTEGER NOT NULL,
    payment_component_id INTEGER NOT NULL,
    PRIMARY KEY (invoice_component_id, payment_component_id),
    FOREIGN KEY (invoice_component_id)
        REFERENCES invoice.invoice_component (id)
        ON DELETE CASCADE,
    FOREIGN KEY (payment_component_id)
        REFERENCES invoice.payment_component (id)
        ON DELETE CASCADE
);

/* A view of all the data in a given invoice. */
DROP VIEW IF EXISTS invoice.account_history;
CREATE VIEW invoice.account_history AS
    SELECT
            invoice.id AS invoice_id,
            charge_journal.transaction_type,
            charge_journal.posting_id AS posting_id,
            charge.id AS component_id,
            charge_journal.occurred,
            (charge_journal.amount * -1)::MONEY AS amount
        FROM
            invoice.invoice
        INNER JOIN
            invoice.invoice_component AS charge ON (charge.invoice_id = invoice.id)
        INNER JOIN
            accounting_view.journal AS charge_journal ON (charge.posting_id = charge_journal.posting_id)
        WHERE
            charge_journal.transaction_type IN ('CHARGE', 'CREDIT NOTE', 'TRANSFER')
    UNION
    SELECT
            invoice.id AS invoice_id,
            payment_journal.transaction_type,
            payment_journal.posting_id AS posting_id,
            payment.id AS component_id,
            payment_journal.occurred,
            payment_journal.amount AS amount
        FROM
            invoice.invoice
        INNER JOIN
            invoice.invoice_component AS charge ON (charge.invoice_id = invoice.id)
        LEFT JOIN
            accounting_view.journal AS charge_journal ON (charge.posting_id = charge_journal.posting_id)
        LEFT JOIN
            invoice.invoice_payment AS payment_link ON (charge.id = payment_link.invoice_component_id)
        LEFT JOIN
            invoice.payment_component AS payment ON (payment.id = payment_link.payment_component_id)
        LEFT JOIN
            accounting_view.journal AS payment_journal ON (payment.posting_id = payment_journal.posting_id)
        WHERE
            charge_journal.transaction_type IN ('CHARGE', 'CREDIT NOTE', 'TRANSFER');


/* should be easy to see if an invoice is paid or outstanding. */
CREATE VIEW invoice.invoice_summary AS
SELECT
    invoice_id,
    (SUM(amount) = '0'::MONEY) AS paid,
    (SUM(amount) FILTER (WHERE amount < '0'::MONEY) * -1) AS total,
    (SUM(amount)*-1) AS outstanding
FROM
    invoice.account_history
GROUP BY invoice_id;

CREATE VIEW invoice.invoice_details AS
SELECT
    invoice_item.invoice_id,
    invoice_item.posting_id,
    charge.credit_amount AS amount,
    charge.credit_amount <= SUM(payment.credit_amount) AS paid,
    SUM(payment.credit_amount) AS amount_paid
FROM
    invoice.invoice_component AS invoice_item
INNER JOIN
    accounting.posting_credit AS charge ON (invoice_item.posting_id = charge.id)
LEFT JOIN
    invoice.invoice_payment AS link ON (invoice_item.id = link.invoice_component_id)
LEFT JOIN
    invoice.payment_component AS payment_item ON (link.payment_component_id = payment_item.id)
LEFT JOIN
    accounting.posting_credit AS payment ON (payment_item.posting_id = payment.id)
GROUP BY
    invoice_item.invoice_id,
    invoice_item.posting_id,
    charge.credit_amount;
/* FIXME: should be easy to tell if payment is used or empty. */
