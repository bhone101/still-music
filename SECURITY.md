# Security reporting

Still Music is an early preview. Security fixes are developed against the latest source; there is no guaranteed response time or long-term support policy yet.

For a suspected vulnerability, use the repository's **Security → Report a vulnerability** option when available. If private reporting is unavailable, open an issue asking for a private reporting channel without posting exploit details, private files or credentials.

Include the affected version, macOS version, a minimal reproduction and the impact. Prefer generated audio samples. Do not include signing credentials, personal music or unredacted library files.

File parsers, metadata writes, library persistence and network response handling are particularly important areas to review. Passing automated checks is not a security certification.
