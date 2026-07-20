# Security policy

## Supported scope

This repository is a small educational utility. Security fixes are applied to the current default branch; there are no maintained release branches.

## Reporting a vulnerability

Please avoid publishing live credentials, private keys, generated OpenVPN profiles, public endpoints tied to a private deployment, or exploit details in a public issue.

Report the problem privately through GitHub's security reporting feature when available, or contact the repository owner through the contact methods listed on the GitHub profile.

Include:

- the affected file and revision;
- a concise description of the impact;
- safe reproduction steps using dummy data;
- a suggested remediation, when known.

## Accidental secret exposure

If a client profile, CA key, private key, token, or environment file is committed, deleting the file in a later commit is not sufficient because it remains in Git history.

Treat exposed material as compromised:

1. revoke and replace the affected certificate or credential;
2. rotate related secrets;
3. remove the sensitive blob from repository history;
4. review access logs and connected systems;
5. invalidate cached or published copies where possible.
