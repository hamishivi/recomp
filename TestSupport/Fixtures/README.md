# Synthetic backup interoperability fixture

`backup-reference.recompbackup` contains an empty synthetic diary under bundle ID
`test.recomp.backupfixture`. Password: `synthetic fixture password only`.
No real personal records, API credentials or passwords are included.

Generated independently with Python cryptography PBKDF2-HMAC-SHA256 (600,000 rounds,
32-byte key), salt bytes 0...15, nonce bytes 0...11, AES-256-GCM and the authenticated
header defined in BackupEnvelope.swift. The fixed salt/nonce are TEST FIXTURE ONLY;
production BackupCrypto always generates fresh random material.

The Python reference encrypt/decrypt and tamper check ran on Linux. That does NOT
verify Apple's native implementation. Run scripts/check-backup-mac.sh on macOS to
check exact CryptoKit/CommonCrypto interoperability, round trips and wrong-password /
tampered-data rejection. Do not import this fixture into your personal installation.
