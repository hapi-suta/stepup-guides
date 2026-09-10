# Instructor: prepare and connect the app

[Classroom home](README.md)

## INSTRUCTOR ONLY — PREPARE AND CONNECT THE APP

Students do not run the following application-server steps.
Install the application software using the app preparation steps in this appendix.
Configure the app to reach the student router on TCP 5432. Ensure db-router-1
resolves to that student router from the app server, or replace db-router-1 in
DataSource with the actual 172.31.31.45. Never point it directly at a PG node.
Use the database password agreed with the student. Provide the app URL only after
the ping check and a browser sign-in/post/reload check succeed.
Changing the app SiteURL alone does not connect it to PostgreSQL.


## 22. Connect Mattermost to HAProxy

**SERVER: mattermost-1 | START AS: ec2-user in Linux**


The application must use the stable writer endpoint rather than a PostgreSQL node address.


```bash
sudo vi /opt/mattermost/config/config.json
```


Edit the existing SqlSettings and ServiceSettings objects to match these
fields. Keep other existing settings. If no config exists, this is the minimal
lab configuration. Use the SAME password you set with \password mattermost.
The app connects to db-router-1, never directly to pg-ha-1.
sslmode=disable matches this isolated lab; it does not encrypt database traffic.


```json
{
  "SqlSettings": {
    "DriverName": "postgres",
    "DataSource": "postgres://mattermost:REPLACE_MATTERMOST_DATABASE_PASSWORD@db-router-1:5432/mattermost?sslmode=disable&connect_timeout=10"
  },
  "ServiceSettings": {
    "ListenAddress": ":8065",
    "SiteURL": ""
  }
}
```


What happens: Apply the supplied SQL and listen settings to the installed Mattermost configuration. The database password resolves through a protected field and is never rendered into chat.


```bash
sudo chown mattermost:mattermost /opt/mattermost/config/config.json
```



```bash
sudo chmod 0600 /opt/mattermost/config/config.json
```


**Check:**

```bash
sudo python3 -m json.tool /opt/mattermost/config/config.json /dev/null
```


Look for: No error is printed and the Linux prompt returns. A parsing error means the JSON must be corrected.
python3 parses the JSON file and sends formatted output to /dev/null. This checks syntax without displaying the password-bearing configuration. It does not test the database connection.

Expected: The protected configuration targets db-router-1:5432 and remains readable only by the mattermost account.


## 23. Start and prove Mattermost

**SERVER: mattermost-1 | START AS: ec2-user in Linux**


The completed BUILD must prove the real application path, not only database processes.


```bash
sudo systemctl daemon-reload
```


Reload systemd so it sees the saved unit. This does not start the service.


```bash
sudo systemctl enable mattermost
```


Enable startup after reboot.


```bash
sudo systemctl start mattermost
```


Start the service now.

What happens: Enable and start Mattermost; its startup migrations and health endpoint exercise the HAProxy-to-PostgreSQL path.

**Check:**

```bash
systemctl status mattermost --no-pager
```


Look for: Loaded: loaded (... ; enabled ...) and Active: active (running)
Read the Loaded and Active lines in the full status output. Loaded identifies the unit; Active reports the current service state.

Expected: Mattermost reports active, its system ping returns OK and database migrations complete through HAProxy.


## 24. Check Mattermost from the workload node

**SERVER: mattermost-1 | START AS: ec2-user in Linux**


The application is the end-to-end consumer of the HA database path.


```bash
curl -fsS http://127.0.0.1:8065/api/v4/system/ping
```


What happens: curl requests Mattermost’s system ping endpoint on this workload node. 127.0.0.1 means this same machine. -f treats HTTP errors as failure; -s hides the progress meter; -S still shows errors. A successful ping does not prove a workload write succeeds.

Expected: The API reports status OK.

### Checkpoint

- [ ] The app connects to the student router; sign-in, message creation and reload succeed before handing out the URL.

[Classroom home](README.md)
