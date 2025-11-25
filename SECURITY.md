# Security Policy

## Supported Versions

This project is currently in active development. Security updates will be provided for the latest version on the `main` branch.

| Version | Supported          |
| ------- | ------------------ |
| main    | :white_check_mark: |
| < 1.0   | :x:                |

## Security Considerations

### Hardware Access

This project requires **direct hardware access** to USB devices and may require **root/sudo privileges**. This introduces several security considerations:

1. **Physical Hardware Risk**: Direct USB device manipulation can potentially damage hardware if used incorrectly
2. **Privilege Escalation**: Running with root privileges requires careful code review
3. **Kernel Interaction**: Uses kernel modules and drivers that could affect system stability

### Safe Usage Guidelines

**DO:**
- ✅ Test in virtual machines with USB passthrough before using on production hardware
- ✅ Review code changes carefully, especially those touching hardware I/O
- ✅ Use the provided devcontainer for isolated development
- ✅ Run hardware tests only in controlled, non-production environments
- ✅ Keep Intel oneAPI and system libraries up to date

**DON'T:**
- ❌ Run untrusted code with root privileges
- ❌ Test on production systems or critical hardware
- ❌ Enable hardware tests in CI for forked repositories
- ❌ Share privileged credentials or expose USB devices to untrusted code

## CI/CD Security

### Hardware Test Gating

Hardware integration tests are **disabled by default** and only run when:

1. **Workflow Dispatch**: Manual trigger with `run_hardware_tests: true` input
2. **PR Label**: Pull requests from the **main repository** (not forks) with the `hardware-tests` label

### Fork Protection

Pull requests from forked repositories **cannot run hardware tests**, even with labels. This prevents:
- Malicious code execution with privileged access
- Unauthorized hardware interaction
- Secret exposure to untrusted contributors

### Secrets Management

- No secrets are used in standard build jobs
- Hardware test jobs must be manually triggered
- Sensitive hardware access is restricted to maintainers

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue:

### Where to Report

**Please DO NOT open a public GitHub issue for security vulnerabilities.**

Instead, report security issues by:

1. **Email**: Contact the maintainers directly (see repository owner information)
2. **GitHub Security Advisory**: Use the "Security" tab to create a private security advisory

### What to Include

When reporting a vulnerability, please include:

- **Description**: Clear description of the vulnerability
- **Impact**: What could an attacker do? What's at risk?
- **Reproduction**: Steps to reproduce the issue
- **Affected Versions**: Which versions are vulnerable?
- **Suggested Fix**: If you have a proposed solution (optional)

### Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial Assessment**: Within 7 days
- **Fix Development**: Depends on severity (critical: days, high: weeks)
- **Public Disclosure**: After patch is released and tested

### Disclosure Policy

- We follow **coordinated disclosure**
- Security issues will be patched before public announcement
- Credit will be given to reporters (unless they prefer to remain anonymous)
- CVE IDs will be requested for significant vulnerabilities

## Known Limitations

### Educational Purpose

This project is intended for **educational and experimental purposes**. It is not production-ready and should not be used in:

- Critical infrastructure
- Production systems
- Medical devices
- Safety-critical applications
- Any environment where failure could cause harm

### Warranty Disclaimer

As stated in the LICENSE and README:

> This project is provided "as is" without any warranties, express or implied. The author disclaims all warranties, including but not limited to implied warranties of merchantability and fitness for a particular purpose.

### Direct Hardware Access

The project uses **direct hardware access** which:
- Bypasses normal operating system protections
- Could potentially cause hardware damage if misused
- Requires root/administrator privileges
- May interact with kernel drivers in unexpected ways

**Use at your own risk!**

## Security Best Practices for Contributors

### Code Review

All contributions should:
- Be reviewed by at least one maintainer
- Include clear descriptions of hardware interactions
- Provide safe test procedures
- Document privilege requirements

### Testing

- Use VMs with USB passthrough for initial testing
- Test with non-critical hardware first
- Provide rollback procedures
- Document expected behaviors and failure modes

### Dependencies

- Keep dependencies minimal and audited
- Use Intel oneAPI from official sources only
- Verify checksums/signatures when possible
- Monitor for security advisories

## Additional Resources

- [Linux USB Gadget Security](https://www.kernel.org/doc/html/latest/usb/gadget.html)
- [USB Security Best Practices](https://www.us-cert.gov/ncas/tips/ST08-001)
- [Intel oneAPI Security Updates](https://www.intel.com/content/www/us/en/security-center/default.html)

## Version History

| Date       | Version | Changes                                    |
|------------|---------|---------------------------------------------|
| 2025-11-25 | 1.0     | Initial security policy                     |

---

**Remember**: With great hardware access comes great responsibility. Always test safely!
