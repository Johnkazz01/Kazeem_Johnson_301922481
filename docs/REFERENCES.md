# References

The following books, official manuals and regulatory documents were used as background material for this portfolio. All references are real; URLs were valid at the time of writing. Section numbers are not cited unless the section number is part of the document's own title.

## Books

1. Garcia-Molina, H., Ullman, J. D., & Widom, J. (2008). *Database Systems: The Complete Book* (2nd ed.). Pearson Prentice Hall.
   - Used for: 3NF design, double-entry ledger modelling, transaction ACID properties.

2. Silberschatz, A., Korth, H. F., & Sudarshan, S. (2020). *Database System Concepts* (7th ed.). McGraw-Hill Education.
   - Used for: concurrency control theory, isolation levels, deadlock prevention by lock ordering.

3. Kleppmann, M. (2017). *Designing Data-Intensive Applications*. O'Reilly Media.
   - Used for: replication (synchronous vs asynchronous), partitioning, and the trade-offs that drive the cloud design in Portfolio 5.

4. Obe, R. & Hsu, L. (2017). *PostgreSQL: Up and Running* (3rd ed.). O'Reilly Media.
   - Used for: PostgreSQL practical configuration, indexing and partitioning.

## Official manuals

5. PostgreSQL Global Development Group. *PostgreSQL 16 Documentation*.
   - https://www.postgresql.org/docs/16/
   - Sections referenced: "Table Partitioning", "Partition Pruning", "Transaction Isolation", "TRIGGER and Constraint Triggers", "Indexing", "EXPLAIN".

6. MongoDB Inc. *MongoDB 7.0 Manual*.
   - https://www.mongodb.com/docs/v7.0/
   - Sections referenced: "$jsonSchema", "Validation", "Aggregation Pipeline", "explain() and Plan Output".

7. psycopg2 documentation. *psycopg 2 Documentation*.
   - https://www.psycopg.org/docs/
   - Used for: `psycopg2.connect`, isolation levels, `IntegrityError` and `OperationalError` handling in `race_demos.py`.

## Nigerian regulation and supervisory guidance

8. Federal Republic of Nigeria. *Nigeria Data Protection Act, 2023*.
   - Available from the Nigeria Data Protection Commission: https://ndpc.gov.ng/
   - Used for: data-protection obligations of the bank as a data controller, and the cross-border transfer safeguards referenced in `cloud_design.md`.

9. Central Bank of Nigeria. *CBN website - Regulations and Guidelines*.
   - https://www.cbn.gov.ng/Supervision/Regulations-and-Guidelines/
   - Used for: supervisory expectations on outsourcing, ICT risk management, and customer-data handling referenced in `cloud_design.md`. Specific circulars are listed by the bank's compliance team in production; no section numbers are cited in this portfolio because they change.

10. Nigeria Data Protection Commission. *NDPC Guidance Notes and Regulations*.
    - https://ndpc.gov.ng/
    - Used for: the operational interpretation of NDPA 2023, including breach notification timelines and data-transfer impact assessments.

## Standards

11. ISO/IEC. *ISO/IEC 27001:2022 Information security management systems*.
    - Used for: the security-control framing around backups, encryption and access management in `cloud_design.md`.

12. PCI Security Standards Council. *PCI DSS v4.0*.
    - Referenced for context only: Lagos Meridian Bank does not store card data, CVV or PINs anywhere in this portfolio, so PCI DSS scope is explicitly out of scope. It is listed here so a reader can see why it was not applied.
