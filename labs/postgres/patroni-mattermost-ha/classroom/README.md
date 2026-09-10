# Patroni HA — classroom guide

Build the database cluster on prepared servers, then connect the instructor's application.

**Start with [1. Prepare your worksheet](01-prepare.md).** Run one command at a time. Every configuration step names the server, provides the file contents and explains how to check the result.

## Who does what?

| Students | Instructor |
|---|---|
| Configure three etcd members | Provision servers and install software/dependencies |
| Configure three PostgreSQL/Patroni members | Supply working networking, TLS certificates and access |
| Configure one HAProxy router | Install and configure Mattermost on the app server |
| Create the app database and verify replication | Connect the app to the student router and provide the app URL |
| Test the app and practice a switchover | Verify the app before handing it over |

## Follow this order

| Milestone | Work | Finish when |
|---|---|---|
| 1 | [Prepare](01-prepare.md) | Server addresses and prerequisites are confirmed |
| 2 | [etcd](02-etcd.md) | Three endpoints report healthy |
| 3 | [Patroni](03-patroni.md) | One leader and two streaming replicas |
| 4 | [HAProxy](04-haproxy.md) | Valid configuration and running router |
| 5 | [Application database](05-app-database.md) | Role, password and database created |
| 6 | [Verify and receive the app](06-verify.md) | Replication and browser checks succeed |
| 7 | [Planned switchover — optional](07-switchover.md) | New leader, same router, working app |

[Read logs and understand settings](08-troubleshooting.md) when a check fails.

## The two addresses

- **Database router IP:** the instructor puts this in the app's database connection.
- **App IP / URL:** students use this to open the app in a browser.

The app IP does not go into the Patroni member list or HAProxy database backends. PostgreSQL sees the router as its client in this topology. The instructor manages any app-to-router network allowlist.

## Instructor material

- [Prepare and connect the app](instructor-app.md)
- [Software installation reference](sysadmin-installation.md)
- [Download the complete plain-text manual](patroni-ha-class-steps.txt)

## Were these steps tested?

The guide is derived from SutaBot's existing Patroni journey and configuration templates. That source contains recorded live outputs for individual checks, including service status and configuration validation. Those records are prior evidence, not a fresh execution of this classroom guide.

**This reorganized manual has not been rehearsed end to end on fresh servers.** Addresses and passwords are worksheet placeholders. The instructor-app handoff is an adaptation of the previous workflow. Documentation checks cover step coverage, configuration preservation, links and separate commands; they do not prove today's servers are ready.

Before calling this class environment ready, verify the prerequisites, run the guide in order and retain the actual results at each checkpoint. Do not interpret an expected-result paragraph as a captured result.
