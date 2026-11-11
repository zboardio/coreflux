-- GENERATED from s7_1500_ob_fault.csv: never edit by hand. Correct the CSV, and the decoder's OB_FAULT_TEXT block with it.
--
-- What the S7-1500's error OBs report, with Siemens' meaning of each code, for both forms of start information: the
-- S7-1500 form (TIA Portal help, "Functional description of S7-1500 CPUs", one page per OB, cited per row) and the
-- classic S7-300/400 form (A5E02789976-01 and A5E02790053-01, page cited). Reproduced meanings, and only some are
-- confirmed on a CPU so far: a code whose meaning disagrees with what your CPU did is a finding, and corrections and
-- additions are welcome as a pull request against the CSV. plc_ob_call (schema.sql) holds the newest call of each OB
-- of a layout-2 DB_PerfDiag, one row per call the reads saw; the view below adds the meanings.
--
-- Idempotent: safe to re-run; the rows are replaced in one transaction. Apply after schema.sql (it needs plc_ob_call)
-- and before role.sql, whose loop also grants SELECT on every plc_* relation to grafana_reader. The writer gets nothing
-- here.
--
-- code: the hex code; for "IO_state bit" the bit number (OB82's IO_state is a WORD of flags), for
-- "Event_Class/Fault_ID" and "Classic EV_CLASS/FLT_ID" Event_Class * 256 + Fault_ID (39 = incoming/removed, 38 =
-- outgoing/inserted), for "Classic fault bit" byte * 8 + bit of the classic OB82's TEMP (bytes 8 to 11).

CREATE TABLE IF NOT EXISTS plc_ob_fault_text (
    ob       smallint NOT NULL,
    field    text     NOT NULL,
    code     integer  NOT NULL,
    code_hex text     NOT NULL,
    meaning  text     NOT NULL,
    source   text     NOT NULL,   -- Siemens' page
    PRIMARY KEY (ob, field, code)
);

BEGIN;
DELETE FROM plc_ob_fault_text;
INSERT INTO plc_ob_fault_text (ob, field, code, code_hex, meaning, source) VALUES
    (80, 'Fault_ID', 1, '16#01', 'Cycle time exceeded', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/time-error-ob-s7-1500'),
    (80, 'Fault_ID', 2, '16#02', 'The requested OB is still being processed', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/time-error-ob-s7-1500'),
    (80, 'Fault_ID', 5, '16#05', 'Expired time interrupt due to time jump', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/time-error-ob-s7-1500'),
    (80, 'Fault_ID', 6, '16#06', 'Expired time interrupt upon re-entry into RUN after HOLD', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/time-error-ob-s7-1500'),
    (80, 'Fault_ID', 7, '16#07', 'Overflow of the OB request buffer for the current priority class', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/time-error-ob-s7-1500'),
    (80, 'Fault_ID', 8, '16#08', 'Isochronous mode interrupt: time error', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/time-error-ob-s7-1500'),
    (80, 'Fault_ID', 9, '16#09', 'Interrupt loss due to high interrupt load', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/time-error-ob-s7-1500'),
    (80, 'Fault_ID', 11, '16#0B', 'Technology synchronization interrupt: time error', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/time-error-ob-s7-1500'),
    (80, 'Fault_ID', 12, '16#0C', 'Cycle time exceeded for the second time (S7-1500 R/H only)', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/time-error-ob-s7-1500'),
    (82, 'IO_state bit', 0, 'bit 0', 'Good', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/diagnostic-interrupt-ob-s7-1500'),
    (82, 'IO_state bit', 1, 'bit 1', 'Deactivated', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/diagnostic-interrupt-ob-s7-1500'),
    (82, 'IO_state bit', 2, 'bit 2', 'Maintenance required', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/diagnostic-interrupt-ob-s7-1500'),
    (82, 'IO_state bit', 3, 'bit 3', 'Maintenance demanded', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/diagnostic-interrupt-ob-s7-1500'),
    (82, 'IO_state bit', 4, 'bit 4', 'Error', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/diagnostic-interrupt-ob-s7-1500'),
    (82, 'IO_state bit', 5, 'bit 5', 'Not available', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/diagnostic-interrupt-ob-s7-1500'),
    (82, 'IO_state bit', 6, 'bit 6', 'Qualified', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/diagnostic-interrupt-ob-s7-1500'),
    (82, 'IO_state bit', 7, 'bit 7', 'Not available', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/diagnostic-interrupt-ob-s7-1500'),
    (82, 'IO_state bit', 15, 'bit 15', 'With bit 4 or 5: 0 network error, 1 hardware error', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/diagnostic-interrupt-ob-s7-1500'),
    (83, 'Event_Class/Fault_ID', 14673, '16#39/16#51', 'IO module removed', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/pull/plug-interrupt-ob-s7-1500'),
    (83, 'Event_Class/Fault_ID', 14676, '16#39/16#54', 'IO submodule removed', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/pull/plug-interrupt-ob-s7-1500'),
    (83, 'Event_Class/Fault_ID', 14420, '16#38/16#54', 'IO submodule inserted, matches the configuration', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/pull/plug-interrupt-ob-s7-1500'),
    (83, 'Event_Class/Fault_ID', 14421, '16#38/16#55', 'Inserted, does not match the configured submodule', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/pull/plug-interrupt-ob-s7-1500'),
    (83, 'Event_Class/Fault_ID', 14422, '16#38/16#56', 'Inserted, error in module parameter assignment', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/pull/plug-interrupt-ob-s7-1500'),
    (83, 'Event_Class/Fault_ID', 14423, '16#38/16#57', 'Inserted, with fault or maintenance', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/pull/plug-interrupt-ob-s7-1500'),
    (83, 'Event_Class/Fault_ID', 14424, '16#38/16#58', 'IO submodule, access error corrected', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/pull/plug-interrupt-ob-s7-1500'),
    (83, 'Event_Class/Fault_ID', 14689, '16#39/16#61', 'Module removed or not responding', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/pull/plug-interrupt-ob-s7-1500'),
    (83, 'Event_Class/Fault_ID', 14433, '16#38/16#61', 'Module inserted', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/pull/plug-interrupt-ob-s7-1500'),
    (83, 'Event_Class/Fault_ID', 13159, '16#33/16#67', 'R/H CiR reparameterization started', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/pull/plug-interrupt-ob-s7-1500'),
    (83, 'Event_Class/Fault_ID', 12903, '16#32/16#67', 'R/H CiR reparameterization finished', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/pull/plug-interrupt-ob-s7-1500'),
    (83, 'Event_Class/Fault_ID', 12904, '16#32/16#68', 'R/H CiR reparameterization rejected', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/pull/plug-interrupt-ob-s7-1500'),
    (83, 'Event_Class/Fault_ID', 14705, '16#39/16#71', 'R/H central module removed', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/pull/plug-interrupt-ob-s7-1500'),
    (83, 'Event_Class/Fault_ID', 14450, '16#38/16#72', 'R/H central module inserted', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/pull/plug-interrupt-ob-s7-1500'),
    (83, 'Event_Class/Fault_ID', 14451, '16#38/16#73', 'R/H central module inserted with a fault', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/pull/plug-interrupt-ob-s7-1500'),
    (86, 'Event_Class/Fault_ID', 14787, '16#39/16#C3', 'DP master system failure', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/rack-error-ob-s7-1500'),
    (86, 'Event_Class/Fault_ID', 14788, '16#39/16#C4', 'DP slave failure', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/rack-error-ob-s7-1500'),
    (86, 'Event_Class/Fault_ID', 14532, '16#38/16#C4', 'DP slave return', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/rack-error-ob-s7-1500'),
    (86, 'Event_Class/Fault_ID', 14794, '16#39/16#CA', 'PROFINET IO system failure', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/rack-error-ob-s7-1500'),
    (86, 'Event_Class/Fault_ID', 14795, '16#39/16#CB', 'PROFINET IO device failure', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/rack-error-ob-s7-1500'),
    (86, 'Event_Class/Fault_ID', 14539, '16#38/16#CB', 'PROFINET IO device return', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/rack-error-ob-s7-1500'),
    (86, 'Event_Class/Fault_ID', 14540, '16#38/16#CC', 'PN IO device returned with fault or maintenance', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/rack-error-ob-s7-1500'),
    (86, 'Event_Class/Fault_ID', 14541, '16#38/16#CD', 'PN IO device returned with a preset/actual configuration difference', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/rack-error-ob-s7-1500'),
    (86, 'Event_Class/Fault_ID', 14542, '16#38/16#CE', 'PN IO device returned with an error in module configuration', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/rack-error-ob-s7-1500'),
    (86, 'Event_Class/Fault_ID', 14840, '16#39/16#F8', 'Some submodules of a PN I-device failed', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/rack-error-ob-s7-1500'),
    (86, 'Event_Class/Fault_ID', 14584, '16#38/16#F8', 'Some submodules of a PN I-device returned', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/rack-error-ob-s7-1500'),
    (86, 'Event_Class/Fault_ID', 14585, '16#38/16#F9', 'Some submodules of a PN I-device returned with a configuration difference', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/rack-error-ob-s7-1500'),
    (121, 'Fault_ID', 0, '16#00', 'Maximum nesting depth of block calls exceeded', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 3, '16#03', 'NULL pointer used to address an operand', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 4, '16#04', 'Unknown instruction', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 5, '16#05', 'Stop instruction', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 32, '16#20', 'Addressed string has incorrect length information', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 33, '16#21', 'BCD conversion error', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 34, '16#22', 'Area length error when reading', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 35, '16#23', 'Area length error when writing', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 36, '16#24', 'Area error when reading', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 37, '16#25', 'Area error when writing', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 38, '16#26', 'Error in timer number', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 39, '16#27', 'Error in counter number', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 40, '16#28', 'Read access to byte/word/dword with a pointer whose bit address is not zero', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 41, '16#29', 'Access to byte/word/dword with a pointer whose bit address is not zero (printed twice by Siemens; presumably the write case)', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 44, '16#2C', 'NULL pointer', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 48, '16#30', 'Write access to a write-protected global DB', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 49, '16#31', 'Write access to a write-protected instance DB', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 50, '16#32', 'DB number error, global DB', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 51, '16#33', 'DB number error, instance DB', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 52, '16#34', 'Number error during FC call', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 53, '16#35', 'Number error during FB call', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 56, '16#38', 'Type-safe DB not loaded', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 57, '16#39', 'DB not defined as type-safe', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 58, '16#3A', 'Access to a DB that is not loaded', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 59, '16#3B', 'DB does not exist', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 60, '16#3C', 'FC not loaded', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 61, '16#3D', 'SFC not loaded', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 62, '16#3E', 'FB not loaded', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 63, '16#3F', 'SFB not available', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 80, '16#50', 'Type-safe DB not loaded', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 81, '16#51', 'DB not type-safe', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 117, '16#75', 'Maximum nesting depth exceeded', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 118, '16#76', 'Maximum available local data exceeded', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 119, '16#77', 'Block call with unsuitable parameter interface', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 161, '16#A1', 'Write access to a write-protected tag', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Fault_ID', 162, '16#A2', 'Access to a tag with an invalid numerical value', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'BlockType', 1, '16#01', 'OB', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'BlockType', 2, '16#02', 'FC', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'BlockType', 3, '16#03', 'FB', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'BlockType', 4, '16#04', 'SFC', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'BlockType', 5, '16#05', 'SFB', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'BlockType', 6, '16#06', 'DB', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (122, 'BlockType', 1, '16#01', 'OB', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/i/o-access-error-ob-s7-1500'),
    (122, 'BlockType', 2, '16#02', 'FC', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/i/o-access-error-ob-s7-1500'),
    (122, 'BlockType', 3, '16#03', 'FB', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/i/o-access-error-ob-s7-1500'),
    (122, 'BlockType', 4, '16#04', 'SFC', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/i/o-access-error-ob-s7-1500'),
    (122, 'BlockType', 5, '16#05', 'SFB', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/i/o-access-error-ob-s7-1500'),
    (122, 'BlockType', 6, '16#06', 'DB', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/i/o-access-error-ob-s7-1500'),
    (122, 'Fault_ID', 66, '16#42', 'I/O access error, reading', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/i/o-access-error-ob-s7-1500'),
    (122, 'Fault_ID', 67, '16#43', 'I/O access error, writing', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/i/o-access-error-ob-s7-1500'),
    (122, 'Area', 1, '16#01', 'Direct (peripheral) access to inputs', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/i/o-access-error-ob-s7-1500'),
    (122, 'Area', 2, '16#02', 'Direct (peripheral) access to outputs', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/i/o-access-error-ob-s7-1500'),
    (122, 'Area', 129, '16#81', 'Access to the process image of the inputs', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/i/o-access-error-ob-s7-1500'),
    (122, 'Area', 130, '16#82', 'Access to the process image of the outputs', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/i/o-access-error-ob-s7-1500'),
    (122, 'Reaction', 0, '16#00', 'Ignore', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/i/o-access-error-ob-s7-1500'),
    (122, 'Reaction', 1, '16#01', 'Replace the incorrect value', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/i/o-access-error-ob-s7-1500'),
    (122, 'Reaction', 2, '16#02', 'Skip the command', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/i/o-access-error-ob-s7-1500'),
    (121, 'Reaction', 0, '16#00', 'Ignore', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Reaction', 1, '16#01', 'Replace the incorrect value', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Reaction', 2, '16#02', 'Skip the command', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (121, 'Reaction', 3, '16#03', 'Programmed error handling', 'https://docs.tia.siemens.cloud/r/en-us/v21/functional-description-of-s7-1500-cpus-s7-1500/organization-blocks-s7-1500/description-of-all-types-of-organization-blocks-s7-1500/programming-error-ob-s7-1500'),
    (80, 'Classic FLT_ID', 1, '16#01', 'Cycle time exceeded', 'A5E02789976-01 §1.16 p.50-52'),
    (80, 'Classic FLT_ID', 2, '16#02', 'The called OB is still being executed', 'A5E02789976-01 §1.16 p.50-52'),
    (80, 'Classic FLT_ID', 5, '16#05', 'Elapsed time-of-day interrupt due to moving the clock forward', 'A5E02789976-01 §1.16 p.50-52'),
    (80, 'Classic FLT_ID', 6, '16#06', 'Elapsed time-of-day interrupt on return to RUN after HOLD', 'A5E02789976-01 §1.16 p.50-52'),
    (80, 'Classic FLT_ID', 7, '16#07', 'Overflow of OB request buffer for the current priority class', 'A5E02789976-01 §1.16 p.50-52'),
    (80, 'Classic FLT_ID', 8, '16#08', 'Synchronous-cycle interrupt time error', 'A5E02789976-01 §1.16 p.50-52'),
    (80, 'Classic FLT_ID', 9, '16#09', 'Interrupt loss due to high interrupt load', 'A5E02789976-01 §1.16 p.50-52'),
    (80, 'Classic FLT_ID', 10, '16#0A', 'Resume RUN after CiR', 'A5E02789976-01 §1.16 p.50-52'),
    (80, 'Classic FLT_ID', 11, '16#0B', 'Technology synchronization interrupt', 'A5E02789976-01 §1.16 p.50-52'),
    (82, 'Classic EV_CLASS/FLT_ID', 14658, '16#39/16#42', 'Diagnostic interrupt, incoming event: a problem, or a component requires maintenance', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic EV_CLASS/FLT_ID', 14402, '16#38/16#42', 'Diagnostic interrupt, outgoing event: no problem and no maintenance left', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 64, 'bit 8.0', 'Module is defective', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 65, 'bit 8.1', 'Internal fault', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 66, 'bit 8.2', 'External fault', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 67, 'bit 8.3', 'Channel fault', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 68, 'bit 8.4', 'External voltage failed', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 69, 'bit 8.5', 'Front panel connector not plugged in', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 70, 'bit 8.6', 'Module is not configured', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 71, 'bit 8.7', 'Incorrect parameters on module', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 76, 'bit 9.4', 'Channel information exists', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 77, 'bit 9.5', 'User information exists', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 78, 'bit 9.6', 'Diagnostic interrupt from substitute', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 79, 'bit 9.7', 'Maintenance required', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 80, 'bit 10.0', 'Submodule is missing or has an error', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 81, 'bit 10.1', 'Communication problem', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 82, 'bit 10.2', 'Module in STOP', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 83, 'bit 10.3', 'Watchdog timer responded', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 84, 'bit 10.4', 'Internal power supply failed', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 85, 'bit 10.5', 'Battery exhausted', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 86, 'bit 10.6', 'Entire backup failed', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 87, 'bit 10.7', 'Maintenance demanded', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 88, 'bit 11.0', 'Expansion rack failure', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 89, 'bit 11.1', 'Processor failure', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 90, 'bit 11.2', 'EPROM fault', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 91, 'bit 11.3', 'RAM fault', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 92, 'bit 11.4', 'ADC/DAC error', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 93, 'bit 11.5', 'Fuse tripped', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic fault bit', 94, 'bit 11.6', 'Hardware interrupt lost', 'A5E02789976-01 §1.18 p.55-56'),
    (82, 'Classic module class', 0, '16#00', 'CPU', 'A5E02790053-01 §33.2 p.692'),
    (82, 'Classic module class', 3, '16#03', 'DP standard slave', 'A5E02790053-01 §33.2 p.692'),
    (82, 'Classic module class', 4, '16#04', 'IM', 'A5E02790053-01 §33.2 p.692'),
    (82, 'Classic module class', 5, '16#05', 'Analog module', 'A5E02790053-01 §33.2 p.692'),
    (82, 'Classic module class', 8, '16#08', 'Function module', 'A5E02790053-01 §33.2 p.692'),
    (82, 'Classic module class', 11, '16#0B', 'I slave', 'A5E02790053-01 §33.2 p.692'),
    (82, 'Classic module class', 12, '16#0C', 'CP', 'A5E02790053-01 §33.2 p.692'),
    (82, 'Classic module class', 15, '16#0F', 'Digital module', 'A5E02790053-01 §33.2 p.692'),
    (83, 'Classic EV_CLASS/FLT_ID', 14673, '16#39/16#51', 'PROFINET IO module removed', 'A5E02789976-01 §1.19 p.58-60'),
    (83, 'Classic EV_CLASS/FLT_ID', 14676, '16#39/16#54', 'PROFINET IO submodule removed', 'A5E02789976-01 §1.19 p.58-60'),
    (83, 'Classic EV_CLASS/FLT_ID', 14420, '16#38/16#54', 'PROFINET IO submodule inserted and matches configured submodule', 'A5E02789976-01 §1.19 p.58-60'),
    (83, 'Classic EV_CLASS/FLT_ID', 14421, '16#38/16#55', 'PROFINET IO submodule inserted, but does not match configured submodule', 'A5E02789976-01 §1.19 p.58-60'),
    (83, 'Classic EV_CLASS/FLT_ID', 14422, '16#38/16#56', 'PROFINET IO submodule inserted, but error with module parameters', 'A5E02789976-01 §1.19 p.58-60'),
    (83, 'Classic EV_CLASS/FLT_ID', 14424, '16#38/16#58', 'PROFINET IO submodule, access error corrected', 'A5E02789976-01 §1.19 p.58-60'),
    (83, 'Classic EV_CLASS/FLT_ID', 14689, '16#39/16#61', 'Module removed or not responding', 'A5E02789976-01 §1.19 p.58-60'),
    (83, 'Classic EV_CLASS/FLT_ID', 14433, '16#38/16#61', 'Module inserted. Module type OK', 'A5E02789976-01 §1.19 p.58-60'),
    (83, 'Classic EV_CLASS/FLT_ID', 14435, '16#38/16#63', 'Module inserted but incorrect module type', 'A5E02789976-01 §1.19 p.58-60'),
    (83, 'Classic EV_CLASS/FLT_ID', 14436, '16#38/16#64', 'Module inserted but problem (module ID cannot be read)', 'A5E02789976-01 §1.19 p.58-60'),
    (83, 'Classic EV_CLASS/FLT_ID', 14437, '16#38/16#65', 'Module inserted but error in module parameter assignment', 'A5E02789976-01 §1.19 p.58-60'),
    (83, 'Classic EV_CLASS/FLT_ID', 14694, '16#39/16#66', 'Module not responding, load voltage error', 'A5E02789976-01 §1.19 p.58-60'),
    (83, 'Classic EV_CLASS/FLT_ID', 14438, '16#38/16#66', 'Module responds again, load voltage error corrected', 'A5E02789976-01 §1.19 p.58-60'),
    (83, 'Classic EV_CLASS/FLT_ID', 13159, '16#33/16#67', 'Start of module reconfiguration', 'A5E02789976-01 §1.19 p.58-60'),
    (83, 'Classic EV_CLASS/FLT_ID', 12903, '16#32/16#67', 'End of module reconfiguration', 'A5E02789976-01 §1.19 p.58-60'),
    (83, 'Classic EV_CLASS/FLT_ID', 14696, '16#39/16#68', 'Module reconfiguration terminated with error', 'A5E02789976-01 §1.19 p.58-60'),
    (86, 'Classic EV_CLASS/FLT_ID', 14785, '16#39/16#C1', 'Expansion rack failure', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 14529, '16#38/16#C1', 'Expansion rack operational again', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 14530, '16#38/16#C2', 'Expansion rack operational again, with a discrepancy between expected and actual configuration', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 14787, '16#39/16#C3', 'Distributed I/O: failure of a DP master system', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 14788, '16#39/16#C4', 'Failure of a DP station', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 14532, '16#38/16#C4', 'Return of a DP station', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 14789, '16#39/16#C5', 'Return of the station, but station faulty', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 14533, '16#38/16#C5', 'Return of the station, but station faulty', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 14534, '16#38/16#C6', 'Expansion rack operational again, but still an error with module parameters', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 14535, '16#38/16#C7', 'Return of a DP station, but error in module parameter assignment', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 14536, '16#38/16#C8', 'Return of a DP station, however discrepancy in configured and actual configuration', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 13001, '16#32/16#C9', 'Enabling a DP slave with SFC 12 D_ACT_DP, MODE=3', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 13257, '16#33/16#C9', 'Disabling a DP slave with SFC 12 D_ACT_DP, MODE=4', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 14794, '16#39/16#CA', 'PROFINET IO system failure', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 14795, '16#39/16#CB', 'PROFINET IO station failure', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 14539, '16#38/16#CB', 'PROFINET IO station return', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 14796, '16#39/16#CC', 'PROFINET IO station return with problem', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 14540, '16#38/16#CC', 'PROFINET IO station return with problem', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 14541, '16#38/16#CD', 'PROFINET IO station return, expected and actual configuration differ', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 14542, '16#38/16#CE', 'PROFINET IO station return, error in module configuration parameters', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 13007, '16#32/16#CF', 'Enabling a PROFINET IO device with SFC 12 D_ACT_DP, MODE=3', 'A5E02789976-01 §1.22 p.66-70'),
    (86, 'Classic EV_CLASS/FLT_ID', 13263, '16#33/16#CF', 'Disabling a PROFINET IO device with SFC 12 D_ACT_DP, MODE=4', 'A5E02789976-01 §1.22 p.66-70'),
    (121, 'Classic FLT_ID', 33, '16#21', 'BCD conversion error', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic FLT_ID', 34, '16#22', 'Area length error when reading', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic FLT_ID', 35, '16#23', 'Area length error when writing', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic FLT_ID', 36, '16#24', 'Range error when reading', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic FLT_ID', 37, '16#25', 'Range error when writing', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic FLT_ID', 38, '16#26', 'Error for timer number', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic FLT_ID', 39, '16#27', 'Error for counter number', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic FLT_ID', 40, '16#28', 'Read access to a byte, word or double word with a pointer whose bit address is not 0', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic FLT_ID', 41, '16#29', 'Write access to a byte, word or double word with a pointer whose bit address is not 0', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic FLT_ID', 48, '16#30', 'Write access to a write-protected global DB', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic FLT_ID', 49, '16#31', 'Write access to a write-protected instance DB', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic FLT_ID', 50, '16#32', 'DB number error accessing a global DB', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic FLT_ID', 51, '16#33', 'DB number error accessing an instance DB', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic FLT_ID', 52, '16#34', 'FC number error in FC call', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic FLT_ID', 53, '16#35', 'FB number error in FB call', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic FLT_ID', 58, '16#3A', 'Access to a DB that has not been loaded', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic FLT_ID', 60, '16#3C', 'Access to an FC that has not been loaded', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic FLT_ID', 61, '16#3D', 'Access to an SFC that is not available', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic FLT_ID', 62, '16#3E', 'Access to an FB that has not been loaded', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic FLT_ID', 63, '16#3F', 'Access to an SFB that is not available', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic BLK_TYPE', 136, '16#88', 'OB', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic BLK_TYPE', 138, '16#8A', 'DB', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic BLK_TYPE', 140, '16#8C', 'FC', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic BLK_TYPE', 142, '16#8E', 'FB', 'A5E02789976-01 §1.27 p.82-84'),
    (122, 'Classic BLK_TYPE', 136, '16#88', 'OB', 'A5E02789976-01 §1.28 p.85-86'),
    (122, 'Classic BLK_TYPE', 140, '16#8C', 'FC', 'A5E02789976-01 §1.28 p.85-86'),
    (122, 'Classic BLK_TYPE', 142, '16#8E', 'FB', 'A5E02789976-01 §1.28 p.85-86'),
    (121, 'Classic memory area', 0, '16#00', 'I/O area', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic memory area', 1, '16#01', 'process-image input table', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic memory area', 2, '16#02', 'process-image output table', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic memory area', 3, '16#03', 'bit memory', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic memory area', 4, '16#04', 'global DB', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic memory area', 5, '16#05', 'instance DB', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic memory area', 6, '16#06', 'own local data', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic memory area', 7, '16#07', 'local data of caller', 'A5E02789976-01 §1.27 p.82-84'),
    (122, 'Classic memory area', 0, '16#00', 'I/O area', 'A5E02789976-01 §1.28 p.85-86'),
    (122, 'Classic memory area', 1, '16#01', 'process image of the inputs', 'A5E02789976-01 §1.28 p.85-86'),
    (122, 'Classic memory area', 2, '16#02', 'process image of the outputs', 'A5E02789976-01 §1.28 p.85-86'),
    (121, 'Classic access type', 0, '16#00', 'bit access', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic access type', 1, '16#01', 'byte access', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic access type', 2, '16#02', 'word access', 'A5E02789976-01 §1.27 p.82-84'),
    (121, 'Classic access type', 3, '16#03', 'double word access', 'A5E02789976-01 §1.27 p.82-84'),
    (122, 'Classic access type', 0, '16#00', 'bit access', 'A5E02789976-01 §1.28 p.85-86'),
    (122, 'Classic access type', 1, '16#01', 'byte access', 'A5E02789976-01 §1.28 p.85-86'),
    (122, 'Classic access type', 2, '16#02', 'word access', 'A5E02789976-01 §1.28 p.85-86'),
    (122, 'Classic access type', 3, '16#03', 'double word access', 'A5E02789976-01 §1.28 p.85-86'),
    (122, 'Classic FLT_ID', 66, '16#42', 'I/O access error, reading', 'A5E02789976-01 §1.28 p.85-86'),
    (122, 'Classic FLT_ID', 67, '16#43', 'I/O access error, writing', 'A5E02789976-01 §1.28 p.85-86');
COMMIT;

-- The newest call of each error OB with its meaning, in either form of the slot (form: bit 7 of ev_class).
-- S7-1500 start information (FC_PerfFault): OB80 Csg_OBnr, Csg_Prio; OB82 IO_state, LADDR, Channel; OB83/OB86 LADDR;
-- OB121/OB122 BlockNr, BlockType, Area. OB121's Area has no meaning here (the CSV's header says why).
-- Classic start information (FC_PerfFaultClassic, ev_class + 128): OB80 ERROR_INFO, ERR_EV_CLASS:ERR_EV_NUM,
-- OB_PRIORITY:OB_NUM; OB82 MDL_ADDR (bit 15 = output module), TEMP bytes 8:9, 10:11; OB83 MDL_ADDR (bit 15 = output),
-- RACK_NUM, MDL_TYPE; OB86 MDL_ADDR, RACKS_FLTD (info2:info3); OB121/OB122 BLK_NUM, BLK_TYPE:area byte, FLT_REG/MEM_ADDR.
-- The columns up to area_text are as before for an S7-1500 row; a classic row fills those that mean the same (csg_*,
-- block_*, area*) and the classic columns after them. details: the start information in words, both forms (what the
-- PLC detail dashboard shows). Dropped and created, so a changed column list applies.
DROP VIEW IF EXISTS plc_ob_call_text;
CREATE VIEW plc_ob_call_text AS
SELECT v.*,
       CASE WHEN v.form = 'S7-1500' THEN
         concat_ws(', ', CASE WHEN v.csg_ob IS NOT NULL THEN 'caused by OB' || v.csg_ob || ' at priority ' || v.csg_prio END,
                   CASE WHEN v.io_state IS NOT NULL THEN 'IO_state 16#' || upper(lpad(to_hex(v.io_state), 4, '0'))
                                                         || coalesce(' (' || v.io_state_text || ')', '') END,
                   CASE WHEN v.laddr IS NOT NULL THEN 'LADDR ' || v.laddr END, CASE WHEN v.channel IS NOT NULL THEN 'channel ' || v.channel END,
                   CASE WHEN v.block_nr IS NOT NULL THEN coalesce(v.block_type_text, 'block type ' || v.block_type) || ' ' || v.block_nr END,
                   CASE WHEN v.area IS NOT NULL THEN coalesce(v.area_text, 'area 16#' || upper(to_hex(v.area))) END)
       ELSE
         concat_ws(', ', 'classic',
                   CASE WHEN v.ob_nr = 80 THEN CASE v.fault_id WHEN 1 THEN 'cycle ' || v.error_info || ' ms'
                                                               WHEN 10 THEN 'CiR synchronization ' || v.error_info || ' ms'
                                                               WHEN 5 THEN 'time-of-day interrupts 16#' || upper(lpad(to_hex(v.error_info), 4, '0'))
                                                               WHEN 6 THEN 'time-of-day interrupts 16#' || upper(lpad(to_hex(v.error_info), 4, '0'))
                                                               ELSE 'error info 16#' || upper(lpad(to_hex(v.error_info), 4, '0')) END END,
                   CASE WHEN v.err_event IS NOT NULL THEN 'start event ' || v.err_event END,
                   CASE WHEN v.csg_ob IS NOT NULL THEN 'caused by OB' || v.csg_ob || ' at priority ' || v.csg_prio END,
                   CASE WHEN v.ob_nr = 82 THEN v.io_dir || ' module ' || v.mdl_addr END,
                   CASE WHEN v.ob_nr = 83 THEN v.io_dir || ' address ' || v.mdl_addr END,
                   CASE WHEN v.ob_nr = 86 THEN CASE WHEN v.fault_id IN (193, 194, 198) THEN 'IM address '
                                                    WHEN v.fault_id BETWEEN 195 AND 201 THEN 'DP master address '
                                                    WHEN v.fault_id BETWEEN 202 AND 207 THEN 'IO controller address '
                                                    ELSE 'MDL_ADDR ' END || v.mdl_addr END,
                   v.station, v.fault_bits_text,
                   CASE WHEN v.module_class_text IS NOT NULL THEN 'module class ' || v.module_class_text END,
                   CASE WHEN v.ob_nr = 83 THEN 'module type 16#' || upper(lpad(to_hex(v.info3), 4, '0')) END,
                   CASE WHEN v.block_nr IS NOT NULL THEN coalesce(v.block_type_text, 'block type 16#' || upper(lpad(to_hex(v.block_type), 2, '0')))
                                                         || ' ' || v.block_nr END,
                   v.area_text,
                   CASE WHEN v.mem_addr IS NOT NULL THEN 'address ' || v.mem_addr END,
                   CASE WHEN v.flt_reg IS NOT NULL THEN 'FLT_REG 16#' || upper(lpad(to_hex(v.flt_reg), 4, '0')) END)
       END AS details
FROM (
SELECT c.ts_plc, c.ts_received, c.plc_id, c.via, c.ob_nr, c.calls, c.ev_class, c.fault_id, c.info1, c.info2, c.info3,
       'OB' || c.ob_nr AS ob,
       CASE WHEN NOT k.classic THEN
         coalesce(CASE WHEN c.ob_nr IN (83, 86) THEN '16#' || upper(lpad(to_hex(c.ev_class::integer), 2, '0')) || '/' END, '')
           || '16#' || upper(lpad(to_hex(c.fault_id::integer), 2, '0'))
       ELSE
         coalesce(CASE WHEN c.ob_nr IN (82, 83, 86) THEN '16#' || upper(lpad(to_hex(k.ev), 2, '0')) || '/' END, '')
           || '16#' || upper(lpad(to_hex(c.fault_id::integer), 2, '0'))
       END AS fault_code,
       f.meaning AS fault_text,
       CASE WHEN c.ob_nr = 80 AND NOT k.classic THEN c.info1 WHEN c.ob_nr = 80 AND c.info3 <> 0 THEN c.info3 & 255 END AS csg_ob,
       CASE WHEN c.ob_nr = 80 AND NOT k.classic THEN c.info2 WHEN c.ob_nr = 80 AND c.info3 <> 0 THEN c.info3 >> 8 END AS csg_prio,
       CASE WHEN c.ob_nr = 82 AND NOT k.classic THEN c.info1 END AS io_state,
       CASE WHEN c.ob_nr = 82 AND NOT k.classic THEN (SELECT string_agg(s.meaning, ', ' ORDER BY s.code) FROM plc_ob_fault_text s
                                  WHERE s.ob = 82 AND s.field = 'IO_state bit' AND c.info1 & (1 << s.code) <> 0) END AS io_state_text,
       CASE WHEN k.classic THEN NULL WHEN c.ob_nr = 82 THEN c.info2 WHEN c.ob_nr IN (83, 86) THEN c.info1 END AS laddr,
       CASE WHEN c.ob_nr = 82 AND NOT k.classic THEN c.info3 END AS channel,
       CASE WHEN c.ob_nr IN (121, 122) THEN c.info1 END AS block_nr,
       CASE WHEN c.ob_nr IN (121, 122) AND NOT k.classic THEN c.info2 WHEN c.ob_nr IN (121, 122) THEN c.info2 >> 8 END AS block_type,
       b.meaning AS block_type_text,
       CASE WHEN c.ob_nr IN (121, 122) AND NOT k.classic THEN c.info3 WHEN k.area_byte THEN c.info2 & 255 END AS area,
       CASE WHEN NOT k.classic THEN a.meaning WHEN k.area_byte THEN concat_ws(', ', coalesce(ma.meaning, 'area ' || (c.info2 & 15)),
                                                                                 coalesce(at.meaning, 'access type ' || (c.info2 >> 4 & 15))) END AS area_text,
       -- the classic form only
       CASE WHEN k.classic THEN 'classic' ELSE 'S7-1500' END AS form,
       CASE WHEN NOT k.classic THEN NULL WHEN c.ob_nr IN (82, 83) THEN c.info1 & 32767
            WHEN c.ob_nr = 86 THEN CASE WHEN c.info1 > 32767 THEN c.info1 - 65536 ELSE c.info1 END END AS mdl_addr,
       CASE WHEN k.classic AND c.ob_nr IN (82, 83) THEN CASE WHEN c.info1 & 32768 <> 0 THEN 'output' ELSE 'input' END END AS io_dir,
       CASE WHEN k.classic AND c.ob_nr = 80 THEN c.info1 END AS error_info,
       CASE WHEN k.classic AND c.ob_nr = 80 AND c.info2 <> 0 THEN '16#' || upper(lpad(to_hex(c.info2), 4, '0')) END AS err_event,
       CASE WHEN k.classic AND c.ob_nr = 122 THEN c.info3 END AS mem_addr,
       CASE WHEN k.classic AND c.ob_nr = 121 THEN c.info3 END AS flt_reg,
       CASE WHEN k.classic AND c.ob_nr = 82 THEN (SELECT string_agg(s.meaning, ', ' ORDER BY s.code) FROM plc_ob_fault_text s
                                  WHERE s.ob = 82 AND s.field = 'Classic fault bit' AND k.z & (1::bigint << ((11 - s.code / 8) * 8 + s.code % 8)) <> 0) END
         AS fault_bits_text,
       CASE WHEN k.classic AND c.ob_nr = 82 THEN coalesce(mc.meaning, 'class 16#' || upper(to_hex(c.info2 & 15))) END AS module_class_text,
       CASE WHEN NOT k.classic THEN NULL
            WHEN c.ob_nr = 83 AND c.info2 & 32768 <> 0 THEN 'PROFINET IO system ID ' || (c.info2 >> 11 & 15) || ', device ' || (c.info2 & 2047)
            WHEN c.ob_nr = 83 THEN 'rack or DP station 16#' || upper(lpad(to_hex(c.info2), 4, '0'))
            WHEN c.ob_nr = 86 AND c.fault_id IN (193, 194, 198) THEN
              'expansion racks ' || coalesce((SELECT string_agg(n::text, ' ' ORDER BY n) FROM generate_series(1, 21) n WHERE k.z & (1::bigint << n) <> 0), 'none')
              || CASE WHEN k.z & (1::bigint << 30) <> 0 THEN ' and the S5 area' ELSE '' END
            WHEN c.ob_nr = 86 AND c.fault_id = 195 THEN 'DP master system ' || (k.z >> 8 & 255)
            WHEN c.ob_nr = 86 AND c.fault_id BETWEEN 196 AND 201 THEN
              'DP master system ' || (k.z >> 8 & 255) || ', station ' || (k.z & 255) || ', slave address ' || (k.z >> 16 & 32767)
            WHEN c.ob_nr = 86 AND c.fault_id = 202 THEN 'PROFINET IO system ID ' || (k.z >> 11 & 15)
            WHEN c.ob_nr = 86 AND c.fault_id BETWEEN 203 AND 207 THEN
              'PROFINET IO system ID ' || (k.z >> 11 & 15) || ', device ' || (k.z & 2047) || ', station address ' || (k.z >> 16 & 32767)
            WHEN c.ob_nr = 86 THEN 'RACKS_FLTD 16#' || upper(lpad(to_hex(k.z), 8, '0')) END AS station
FROM plc_ob_call c
CROSS JOIN LATERAL (SELECT (c.ev_class & 128) <> 0 AS classic, (c.ev_class & 127)::integer AS ev,
                           (c.info2::bigint << 16) | c.info3 AS z,
                           (c.ev_class & 128) <> 0 AND (c.ob_nr = 122 OR (c.ob_nr = 121 AND c.fault_id IN (34, 35, 40, 41))) AS area_byte) k
LEFT JOIN plc_ob_fault_text f ON f.ob = c.ob_nr
      AND ((NOT k.classic AND ((c.ob_nr IN (80, 121, 122) AND f.field = 'Fault_ID' AND f.code = c.fault_id)
                            OR (c.ob_nr IN (83, 86) AND f.field = 'Event_Class/Fault_ID' AND f.code = c.ev_class * 256 + c.fault_id)))
        OR (k.classic AND ((c.ob_nr IN (80, 121, 122) AND f.field = 'Classic FLT_ID' AND f.code = c.fault_id)
                        OR (c.ob_nr IN (82, 83, 86) AND f.field = 'Classic EV_CLASS/FLT_ID' AND f.code = k.ev * 256 + c.fault_id))))
LEFT JOIN plc_ob_fault_text b ON b.ob = c.ob_nr AND c.ob_nr IN (121, 122)
      AND ((NOT k.classic AND b.field = 'BlockType' AND b.code = c.info2) OR (k.classic AND b.field = 'Classic BLK_TYPE' AND b.code = c.info2 >> 8))
LEFT JOIN plc_ob_fault_text a ON a.ob = c.ob_nr AND a.field = 'Area' AND a.code = c.info3 AND c.ob_nr = 122 AND NOT k.classic
LEFT JOIN plc_ob_fault_text ma ON ma.ob = c.ob_nr AND ma.field = 'Classic memory area' AND ma.code = c.info2 & 15 AND k.area_byte
LEFT JOIN plc_ob_fault_text at ON at.ob = c.ob_nr AND at.field = 'Classic access type' AND at.code = c.info2 >> 4 & 15 AND k.area_byte
LEFT JOIN plc_ob_fault_text mc ON mc.ob = 82 AND mc.field = 'Classic module class' AND mc.code = c.info2 & 15 AND k.classic AND c.ob_nr = 82
) v;

-- role.sql's pattern: SELECT for the reader, when it exists (role.sql creates it, and grants this again on every apply).
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'grafana_reader') THEN
        GRANT SELECT ON plc_ob_fault_text, plc_ob_call_text TO grafana_reader;
    END IF;
END
$$;
