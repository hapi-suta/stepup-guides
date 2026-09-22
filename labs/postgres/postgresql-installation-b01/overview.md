# Install PostgreSQL server and client

Bob is preparing a training database server for the application team. First, he needs to install the software. A successful installation does not mean a database is running yet.

The client, psql, lets you send requests to a database server. The server program, postgres, does the database work. In this lab you install both, but do not start the server.

A package is software prepared for installation on this operating system. A repository is a source from which the package manager downloads it. DNF is the package manager used on this Rocky Linux machine.

Use the Linux terminal on the assigned lab machine, as the normal login user. In this local qualification the user is student. Commands beginning with sudo request administrator permission for that one action; your terminal stays in the same user session.

Type only the command, without a shell prompt such as $. Press Enter once, wait for the command to finish and read its result before continuing. Download progress is normal. Stop on an error and ask SutaBot about that result when using the connected workspace.

The number 18 is the PostgreSQL major version. The .6 in 18.6 is a maintenance release within that major version. This walkthrough was tested with PostgreSQL 18.6 on Rocky Linux 9.8, x86_64. Other systems need their own tested instructions.
