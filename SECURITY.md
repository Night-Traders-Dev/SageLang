# Security Policy

Thank you for helping keep **SageLang** secure.

The security of the SageLang ecosystem—including the compiler, runtime, virtual machine, standard library, tooling, and future SageOS integration—is a top priority. We appreciate responsible disclosure and will work with researchers to resolve legitimate vulnerabilities as quickly as possible.

---

# Supported Versions

Only the latest stable release receives security updates.

| Version | Supported |
|---------|-----------|
| Latest Stable | ✅ |
| Previous Stable | ⚠️ Critical fixes only |
| Development (`main`) | 🚧 Best effort |
| All older releases | ❌ |

> Users are strongly encouraged to upgrade to the latest stable release whenever possible.

---

# Scope

This policy applies to all official SageLang repositories, including but not limited to:

- Compiler
- Runtime
- SageVM
- Standard Library
- SageMake
- SageBoot
- Official tooling
- Official documentation examples
- Official package repositories

Third-party libraries and community projects maintain their own security policies.

---

# Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub Issues or Discussions.**

Instead, report vulnerabilities privately by opening a **GitHub Security Advisory** or by contacting the project maintainers directly through the repository's security reporting mechanism.

When reporting a vulnerability, please include as much information as possible:

- SageLang version
- Operating system
- CPU architecture
- Build configuration
- Steps to reproduce
- Proof of concept (if available)
- Expected behavior
- Actual behavior
- Potential impact
- Suggested mitigation (optional)

A minimal reproducible example greatly improves our ability to investigate the issue.

---

# What to Expect

After receiving a report, we will typically follow this process:

| Stage | Target Time |
|--------|-------------|
| Initial acknowledgment | Within 72 hours |
| Initial assessment | Within 7 days |
| Status updates | At least every 14 days |
| Security fix | As quickly as practical, depending on severity |

Complex vulnerabilities affecting compiler correctness, memory safety, or the runtime may require additional time for investigation and testing.

---

# Responsible Disclosure

Please allow us reasonable time to investigate and develop a fix before publicly disclosing a vulnerability.

We ask that you:

- Do not publicly disclose the issue before a fix is available.
- Do not exploit vulnerabilities beyond what is necessary to demonstrate the issue.
- Do not access, modify, or delete data belonging to others.
- Do not perform denial-of-service attacks against project infrastructure.

We are committed to working collaboratively with security researchers throughout the disclosure process.

---

# Security Priorities

We consider the following issues to be of high priority:

- Remote code execution
- Arbitrary code execution
- Compiler miscompilation resulting in unsafe binaries
- Memory corruption
- Buffer overflows
- Use-after-free
- Double-free vulnerabilities
- Integer overflows leading to unsafe behavior
- Sandbox or VM escapes
- Privilege escalation
- Cryptographic weaknesses
- Package supply-chain attacks
- Build system compromise
- Dependency vulnerabilities affecting official releases

---

# Out of Scope

The following are generally not considered security vulnerabilities:

- Style or formatting issues
- Documentation typos
- Compiler warnings without security impact
- Performance issues without exploitable consequences
- Denial-of-service requiring unrealistic resources
- Vulnerabilities in unsupported versions
- Vulnerabilities in third-party software not maintained by the SageLang project

---

# Security Best Practices

Users are encouraged to:

- Keep SageLang updated to the latest stable release.
- Build from official source repositories.
- Verify downloaded release artifacts when checksums or signatures are provided.
- Use supported toolchains and dependencies.
- Keep build environments and operating systems up to date.

---

# Recognition

We sincerely appreciate responsible security researchers who help improve SageLang.

With the reporter's permission, significant security contributions may be acknowledged in release notes or project documentation after the vulnerability has been resolved.

---

Thank you for helping make SageLang a safer and more reliable platform for everyone.
