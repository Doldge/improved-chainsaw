DROP SCHEMA IF EXISTS accounting_view CASCADE;
CREATE SCHEMA accounting_view;


/* Need a table & validator function for each possible transaction type. */
CREATE OR REPLACE FUNCTION accounting_view.is_valid_charge_journal(arg_posting_credit_id INTEGER)
    RETURNS BOOLEAN AS $_$
DECLARE
    posting_debit_rec RECORD;
    posting_credit_rec RECORD;
    account_debit_rec RECORD;
    account_credit_rec RECORD;
    arg_journal_id INTEGER;
    valid_journal BOOLEAN;
BEGIN
    valid_journal := FALSE;

    SELECT posting_debit.*
        INTO posting_debit_rec
        FROM accounting.posting_debit
        INNER JOIN accounting.posting_credit USING (posting_base_id)
        WHERE posting_credit.id = arg_posting_credit_id;

    arg_journal_id := posting_debit_rec.posting_base_id;
    /* All Journals can only have a single debit posting. */
    IF ((SELECT COUNT(*) FROM accounting.posting_debit WHERE posting_base_id = arg_journal_id) != 1) THEN
        RAISE WARNING 'Multiple Debit Postings Exist';
        RETURN valid_journal;
    END IF;

    SELECT * INTO account_debit_rec FROM accounting.account WHERE account.id = posting_debit_rec.debit_accountid;
    IF ((account_debit_rec.accounttype ~* 'ASSET') IS FALSE) THEN
        /* It's not debting a REVENUE account, can't be a valid charge? */
        RAISE NOTICE 'Not a Revenue Account';
        RETURN valid_journal;
    END IF;

    << credit_posting >>
    FOR posting_credit_rec IN
        SELECT * FROM accounting.posting_credit WHERE posting_base_id = arg_journal_id ORDER BY id
    LOOP
        /* Get the credit account details */
        SELECT * INTO account_credit_rec
        FROM accounting.account WHERE account.id = posting_credit_rec.credit_accountid;
        /* It's not crediting an asset account then it's not a charge? */
        IF ((account_credit_rec.accounttype ~* 'REVENUE') IS FALSE) THEN
            RETURN valid_journal;
        END IF;
    END LOOP;

    valid_journal := TRUE;
    RETURN valid_journal;
END;
$_$ LANGUAGE plpgsql;

DROP TABLE IF EXISTS accounting_view.journal_charge;
CREATE TABLE accounting_view.journal_charge(
    id INTEGER NOT NULL,
    occurred DATE NOT NULL,
    complete BOOLEAN NOT NULL,
    debit_posting_id INTEGER NOT NULL,
    debit_accountid INTEGER NOT NULL,
    posting_id INTEGER NOT NULL,
    credit_accountid INTEGER NOT NULL,
    credit_amount MONEY NOT NULL,
    PRIMARY KEY (id, posting_id),
    FOREIGN KEY (id, occurred, complete)
        REFERENCES accounting.posting_base(id, occurred, complete)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (debit_posting_id, debit_accountid)
        REFERENCES accounting.posting_debit(id, debit_accountid)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (posting_id, credit_accountid, credit_amount)
        REFERENCES accounting.posting_credit(id, credit_accountid, credit_amount)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    UNIQUE(posting_id),
    CONSTRAINT valid_journal CHECK (accounting_view.is_valid_charge_journal(posting_id) IS TRUE)
);


CREATE OR REPLACE FUNCTION accounting_view.is_valid_payment_journal(arg_posting_credit_id INTEGER)
    RETURNS BOOLEAN AS $_$
DECLARE
    posting_debit_rec RECORD;
    posting_credit_rec RECORD;
    account_debit_rec RECORD;
    account_credit_rec RECORD;
    arg_journal_id INTEGER;
    valid_journal BOOLEAN;
BEGIN
    valid_journal := FALSE;

    SELECT posting_debit.*
        INTO posting_debit_rec
        FROM accounting.posting_debit
        INNER JOIN accounting.posting_credit USING (posting_base_id)
        WHERE posting_credit.id = arg_posting_credit_id;

    arg_journal_id := posting_debit_rec.posting_base_id;
    /* All Journals can only have a single debit posting. */
    IF ((SELECT COUNT(*) FROM accounting.posting_debit WHERE posting_base_id = arg_journal_id) != 1) THEN
        RAISE WARNING 'Multiple Debit Postings Exist';
        RETURN valid_journal;
    END IF;

    SELECT * INTO account_debit_rec FROM accounting.account WHERE account.id = posting_debit_rec.debit_accountid;
    IF ((account_debit_rec.accounttype ~* 'LIABILITY') IS FALSE) THEN
        /* It's not debiting a LIABILITY account, then it's not a payment? */
        RETURN valid_journal;
    END IF;

    << credit_posting >>
    FOR posting_credit_rec IN
        SELECT * FROM accounting.posting_credit WHERE posting_base_id = arg_journal_id ORDER BY id
    LOOP
        /* Get the credit account details */
        SELECT * INTO account_credit_rec
        FROM accounting.account WHERE account.id = posting_credit_rec.credit_accountid;
        /* It's not crediting an ASSET account, then it's not a valid payment? */
        IF ((account_credit_rec.accounttype ~* 'ASSET') IS FALSE) THEN
            RETURN valid_journal;
        END IF;
    END LOOP;

    valid_journal := TRUE;
    RETURN valid_journal;
END;
$_$ LANGUAGE plpgsql;

DROP TABLE IF EXISTS accounting_view.journal_payment;
CREATE TABLE accounting_view.journal_payment(
    id INTEGER NOT NULL,
    occurred DATE NOT NULL,
    complete BOOLEAN NOT NULL,
    debit_posting_id INTEGER NOT NULL,
    debit_accountid INTEGER NOT NULL,
    posting_id INTEGER NOT NULL,
    credit_accountid INTEGER NOT NULL,
    credit_amount MONEY NOT NULL,
    PRIMARY KEY (id, posting_id),
    FOREIGN KEY (id, occurred, complete)
        REFERENCES accounting.posting_base(id, occurred, complete)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (debit_posting_id, debit_accountid)
        REFERENCES accounting.posting_debit(id, debit_accountid)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (posting_id, credit_accountid, credit_amount)
        REFERENCES accounting.posting_credit(id, credit_accountid, credit_amount)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    UNIQUE(posting_id),
    CHECK (accounting_view.is_valid_payment_journal(posting_id) IS TRUE)
);


CREATE OR REPLACE FUNCTION accounting_view.is_valid_credit_note_journal(arg_posting_credit_id INTEGER)
    RETURNS BOOLEAN AS $_$
DECLARE
    posting_debit_rec RECORD;
    posting_credit_rec RECORD;
    account_debit_rec RECORD;
    account_credit_rec RECORD;
    arg_journal_id INTEGER;
    valid_journal BOOLEAN;
BEGIN
    valid_journal := FALSE;

    SELECT posting_debit.*
        INTO posting_debit_rec
        FROM accounting.posting_debit
        INNER JOIN accounting.posting_credit USING (posting_base_id)
        WHERE posting_credit.id = arg_posting_credit_id;

    arg_journal_id := posting_debit_rec.posting_base_id;
    /* All Journals can only have a single debit posting. */
    IF ((SELECT COUNT(*) FROM accounting.posting_debit WHERE posting_base_id = arg_journal_id) != 1) THEN
        RAISE WARNING 'Multiple Debit Postings Exist';
        RETURN valid_journal;
    END IF;

    SELECT * INTO account_debit_rec FROM accounting.account WHERE account.id = posting_debit_rec.debit_accountid;
    IF ((account_debit_rec.accounttype ~* 'REVENUE') IS FALSE) THEN
        /* It's not debiting a LIABILITY account, then it's not a credit note? */
        RETURN valid_journal;
    END IF;

    << credit_posting >>
    FOR posting_credit_rec IN
        SELECT * FROM accounting.posting_credit WHERE posting_base_id = arg_journal_id ORDER BY id
    LOOP
        /* Get the credit account details */
        SELECT * INTO account_credit_rec
        FROM accounting.account WHERE account.id = posting_credit_rec.credit_accountid;
        /* It's not crediting an ASSET account, then it's not a valid credit note? */
        IF ((account_credit_rec.accounttype ~* 'ASSET') IS FALSE) THEN
            RETURN valid_journal;
        END IF;
    END LOOP;

    valid_journal := TRUE;
    RETURN valid_journal;
END;
$_$ LANGUAGE plpgsql;

DROP TABLE IF EXISTS accounting_view.journal_credit_note;
CREATE TABLE accounting_view.journal_credit_note(
    id INTEGER NOT NULL,
    occurred DATE NOT NULL,
    complete BOOLEAN NOT NULL,
    debit_posting_id INTEGER NOT NULL,
    debit_accountid INTEGER NOT NULL,
    posting_id INTEGER NOT NULL,
    credit_accountid INTEGER NOT NULL,
    credit_amount MONEY NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (id, occurred, complete)
        REFERENCES accounting.posting_base(id, occurred, complete)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (debit_posting_id, debit_accountid)
        REFERENCES accounting.posting_debit(id, debit_accountid)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (posting_id, credit_accountid, credit_amount)
        REFERENCES accounting.posting_credit(id, credit_accountid, credit_amount)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    UNIQUE(posting_id),
    CHECK (accounting_view.is_valid_credit_note_journal(posting_id) IS TRUE)
);


CREATE OR REPLACE FUNCTION accounting_view.is_valid_debit_note_journal(arg_posting_credit_id INTEGER)
    RETURNS BOOLEAN AS $_$
DECLARE
    posting_debit_rec RECORD;
    posting_credit_rec RECORD;
    account_debit_rec RECORD;
    account_credit_rec RECORD;
    arg_journal_id INTEGER;
    valid_journal BOOLEAN;
BEGIN
    valid_journal := FALSE;

    SELECT posting_debit.*
        INTO posting_debit_rec
        FROM accounting.posting_debit
        INNER JOIN accounting.posting_credit USING (posting_base_id)
        WHERE posting_credit.id = arg_posting_credit_id;

    arg_journal_id := posting_debit_rec.posting_base_id;
    /* All Journals can only have a single debit posting. */
    IF ((SELECT COUNT(*) FROM accounting.posting_debit WHERE posting_base_id = arg_journal_id) != 1) THEN
        RAISE WARNING 'Multiple Debit Postings Exist';
        RETURN valid_journal;
    END IF;

    SELECT * INTO account_debit_rec FROM accounting.account WHERE account.id = posting_debit_rec.debit_accountid;
    IF ((account_debit_rec.accounttype ~* 'ASSET') IS FALSE) THEN
        /* It's not debiting a LIABILITY account, then it's not a debit note? */
        RETURN valid_journal;
    END IF;

    << credit_posting >>
    FOR posting_credit_rec IN
        SELECT * FROM accounting.posting_credit WHERE posting_base_id = arg_journal_id ORDER BY id
    LOOP
        /* Get the credit account details */
        SELECT * INTO account_credit_rec
        FROM accounting.account WHERE account.id = posting_credit_rec.credit_accountid;
        /* It's not crediting an ASSET account, then it's not a valid debit note? */
        IF ((account_credit_rec.accounttype ~* 'LIABILITY') IS FALSE) THEN
            RETURN valid_journal;
        END IF;
    END LOOP;

    valid_journal := TRUE;
    RETURN valid_journal;
END;
$_$ LANGUAGE plpgsql;

DROP TABLE IF EXISTS accounting_view.journal_debit_note;
CREATE TABLE accounting_view.journal_debit_note(
    id INTEGER NOT NULL,
    occurred DATE NOT NULL,
    complete BOOLEAN NOT NULL,
    debit_posting_id INTEGER NOT NULL,
    debit_accountid INTEGER NOT NULL,
    posting_id INTEGER NOT NULL,
    credit_accountid INTEGER NOT NULL,
    credit_amount MONEY NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (id, occurred, complete)
        REFERENCES accounting.posting_base(id, occurred, complete)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (debit_posting_id, debit_accountid)
        REFERENCES accounting.posting_debit(id, debit_accountid)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (posting_id, credit_accountid, credit_amount)
        REFERENCES accounting.posting_credit(id, credit_accountid, credit_amount)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    UNIQUE(posting_id),
    CHECK (accounting_view.is_valid_debit_note_journal(posting_id) IS TRUE)
);


CREATE OR REPLACE FUNCTION accounting_view.is_valid_transfer_journal(arg_posting_credit_id INTEGER)
    RETURNS BOOLEAN AS $_$
DECLARE
    posting_debit_rec RECORD;
    posting_credit_rec RECORD;
    account_debit_rec RECORD;
    account_credit_rec RECORD;
    arg_journal_id INTEGER;
    valid_journal BOOLEAN;
BEGIN
    valid_journal := FALSE;

    SELECT posting_debit.*
        INTO posting_debit_rec
        FROM accounting.posting_debit
        INNER JOIN accounting.posting_credit USING (posting_base_id)
        WHERE posting_credit.id = arg_posting_credit_id;

    arg_journal_id := posting_debit_rec.posting_base_id;
    /* All Journals can only have a single debit posting. */
    IF ((SELECT COUNT(*) FROM accounting.posting_debit WHERE posting_base_id = arg_journal_id) != 1) THEN
        RAISE WARNING 'Multiple Debit Postings Exist';
        RETURN valid_journal;
    END IF;

    SELECT * INTO account_debit_rec FROM accounting.account WHERE account.id = posting_debit_rec.debit_accountid;

    << credit_posting >>
    FOR posting_credit_rec IN
        SELECT * FROM accounting.posting_credit WHERE posting_base_id = arg_journal_id ORDER BY id
    LOOP
        SELECT * INTO account_credit_rec
        FROM accounting.account WHERE account.id = posting_credit_rec.credit_accountid;
        /* It's not crediting an account with the same type as the debited account */
        IF (
            (SELECT (regexp_matches(account_credit_rec.accounttype, '(?:.*)-(.*)'))[1])
            != (SELECT (regexp_matches(account_debit_rec.accounttype, '(?:.*)-(.*)'))[1])
        ) THEN
            RETURN valid_journal;
        END IF;
    END LOOP;

    valid_journal := TRUE;
    RETURN valid_journal;
END;
$_$ LANGUAGE plpgsql;

DROP TABLE IF EXISTS accounting_view.journal_transfer;
CREATE TABLE accounting_view.journal_transfer(
    id INTEGER NOT NULL,
    occurred DATE NOT NULL,
    complete BOOLEAN NOT NULL,
    debit_posting_id INTEGER NOT NULL,
    debit_accountid INTEGER NOT NULL,
    posting_id INTEGER NOT NULL,
    credit_accountid INTEGER NOT NULL,
    credit_amount MONEY NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (id, occurred, complete)
        REFERENCES accounting.posting_base(id, occurred, complete)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (debit_posting_id, debit_accountid)
        REFERENCES accounting.posting_debit(id, debit_accountid)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (posting_id, credit_accountid, credit_amount)
        REFERENCES accounting.posting_credit(id, credit_accountid, credit_amount)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    UNIQUE(posting_id),
    CHECK (accounting_view.is_valid_transfer_journal(posting_id) IS TRUE)
);

/* Move Journals to this table when their voided. */
DROP TABLE IF EXISTS accounting_view.journal_void;
CREATE TABLE accounting_view.journal_void(
    id INTEGER NOT NULL,
    occurred DATE NOT NULL,
    complete BOOLEAN NOT NULL,
    debit_posting_id INTEGER NOT NULL,
    debit_accountid INTEGER NOT NULL,
    posting_id INTEGER NOT NULL,
    credit_accountid INTEGER NOT NULL,
    credit_amount MONEY NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (id, occurred, complete)
        REFERENCES accounting.posting_base(id, occurred, complete)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (debit_posting_id, debit_accountid)
        REFERENCES accounting.posting_debit(id, debit_accountid)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (posting_id, credit_accountid, credit_amount)
        REFERENCES accounting.posting_credit(id, credit_accountid, credit_amount)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    UNIQUE(posting_id)
);


CREATE OR REPLACE FUNCTION accounting_view.is_valid_void_reversal_journal(arg_reversal_journal_id INTEGER, arg_void_journal_id INTEGER)
    RETURNS BOOLEAN AS $_$
DECLARE
    posting_debit_rec RECORD;
    posting_credit_rec RECORD;
    account_debit_rec RECORD;
    account_credit_rec RECORD;
    valid_journal BOOLEAN;
BEGIN
    valid_journal := FALSE;

    /* TODO: check that the 'void_reversal' journal is valid for the given journal. */

    valid_journal := TRUE;
    RETURN valid_journal;
END;

$_$ LANGUAGE plpgsql;
/* Reversal journals, used for balancing the account.
    1 - many relationship with journal_void.
    (a single voided journal can have multiple reversals).
    But the journals should balance, so:
    journal_void - journal_void_reversal = 0.
*/
DROP TABLE IF EXISTS accounting_view.journal_void_reversal;
CREATE TABLE accounting_view.journal_void_reversal(
    id INTEGER NOT NULL,
    occurred DATE NOT NULL,
    complete BOOLEAN NOT NULL,
    debit_posting_id INTEGER NOT NULL,
    debit_accountid INTEGER NOT NULL,
    posting_id INTEGER NOT NULL,
    credit_accountid INTEGER NOT NULL,
    credit_amount MONEY NOT NULL,
    void_for INTEGER NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (id, occurred, complete)
        REFERENCES accounting.posting_base(id, occurred, complete)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (debit_posting_id, debit_accountid)
        REFERENCES accounting.posting_debit(id, debit_accountid)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (posting_id, credit_accountid, credit_amount)
        REFERENCES accounting.posting_credit(id, credit_accountid, credit_amount)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (void_for)
        REFERENCES accounting_view.journal_void(posting_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    UNIQUE(posting_id),
    CHECK (accounting_view.is_valid_void_reversal_journal(id, void_for) IS TRUE)
);


/* Present all the journal types as a single table.
 * (We have them defined separately for relational reasons).
 */
DROP VIEW IF EXISTS accounting_view.journal;
CREATE VIEW accounting_view.journal AS
    SELECT
        id,
        occurred,
        complete,
        debit_posting_id,
        debit_accountid,
        posting_id,
        credit_accountid,
        credit_amount AS amount,
        'CHARGE' AS transaction_type
    FROM
        accounting_view.journal_charge
    UNION
    SELECT
        id,
        occurred,
        complete,
        debit_posting_id,
        debit_accountid,
        posting_id,
        credit_accountid,
        credit_amount AS amount,
        'PAYMENT' AS transaction_type
    FROM
        accounting_view.journal_payment
    UNION
    SELECT
        id,
        occurred,
        complete,
        debit_posting_id,
        debit_accountid,
        posting_id,
        credit_accountid,
        credit_amount AS amount,
        'CREDIT NOTE' AS transaction_type
    FROM
        accounting_view.journal_credit_note
    UNION
    SELECT
        id,
        occurred,
        complete,
        debit_posting_id,
        debit_accountid,
        posting_id,
        credit_accountid,
        credit_amount AS amount,
        'DEBIT NOTE' AS transaction_type
    FROM
        accounting_view.journal_debit_note
    UNION
    SELECT
        id,
        occurred,
        complete,
        debit_posting_id,
        debit_accountid,
        posting_id,
        credit_accountid,
        credit_amount AS amount,
        'TRANSFER' AS transaction_type
    FROM
        accounting_view.journal_transfer
    UNION
    SELECT
        id,
        occurred,
        complete,
        debit_posting_id,
        debit_accountid,
        posting_id,
        credit_accountid,
        credit_amount AS amount,
        CONCAT('VOIDED',
            CASE
            WHEN accounting_view.is_valid_charge_journal(id) IS TRUE
                THEN ' CHARGE'
            WHEN accounting_view.is_valid_payment_journal(id) IS TRUE
                THEN ' PAYMENT'
            WHEN accounting_view.is_valid_debit_note_journal(id) IS TRUE
                THEN ' DEBIT NOTE'
            WHEN accounting_view.is_valid_credit_note_journal(id) IS TRUE
                THEN ' CREDIT NOTE'
            WHEN accounting_view.is_valid_transfer_journal(id) IS TRUE
                THEN ' TRANSFER'
            END
        ) AS transaction_type
    FROM
        accounting_view.journal_void
    ORDER BY
        occurred DESC;
