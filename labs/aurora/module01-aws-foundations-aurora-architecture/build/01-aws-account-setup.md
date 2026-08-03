# Module 01 - AWS Foundations and Aurora Architecture
## Guide 01: AWS Account Setup

**Objective:** Create (or prepare) an AWS account, set up a dedicated IAM user for all lab work, install the AWS CLI, and verify everything works - so you never touch the root account again.
**Time:** 30 minutes
**Prerequisites:** A valid email address and a credit/debit card (AWS requires one even for free tier). A terminal on your local machine (Terminal on Mac, PowerShell on Windows, or any Linux shell).

---

## 1. Create an AWS Account (or Use an Existing One)

If you already have an AWS account, skip to Section 2.

**In your browser** (https://aws.amazon.com):

1. Click **Create an AWS Account** in the top-right corner.
2. Enter your email address and choose an account name (for example: `devops-dba-lab`).
3. AWS will send a verification code to your email. Enter it.
4. Set a strong root password. Use at least 16 characters with uppercase, lowercase, numbers, and symbols. Save this password in a password manager - not a sticky note.
5. Choose **Personal** for account type (unless your company is paying).
6. Enter your payment information. AWS will place a small temporary hold (usually $1 USD) to verify the card. You will not be charged unless you use paid services.
7. Verify your phone number via SMS or voice call.
8. Choose the **Basic (Free)** support plan.
9. Click **Complete sign up**.

You now have an AWS root account. The root user has unlimited access to everything - which is exactly why you should not use it for daily work. The next step is creating a safer IAM user.

---

## 2. Create an IAM User (Not Root)

The root user is like the master key to your entire AWS kingdom. If those credentials are compromised, an attacker can delete everything, spin up expensive resources, or access your billing information. You want to create an IAM user with admin privileges for your lab work and lock away the root credentials.

**In the AWS Console** (IAM > Users):

1. Log into the console at [https://console.aws.amazon.com](https://console.aws.amazon.com) using your root email and password.
2. In the top search bar, type `IAM` and click **IAM** in the results.
3. In the left sidebar, click **Users**.
4. Click the orange **Create user** button in the top-right area.
5. In the **User name** field, type a name for your user. For example: `dba-admin`. Use lowercase letters and hyphens only - no spaces.
6. Check the box **Provide user access to the AWS Management Console**.
7. Under **Console password**, select **Custom password** and type a strong password.
8. Uncheck **Users must create a new password at next sign-in** (this is your own account).
9. Click **Next**.
10. On the **Set permissions** page, click **Attach policies directly**.
11. In the search box under **Permissions policies**, type `AdministratorAccess`.
12. Check the box next to **AdministratorAccess** in the results list.

    > **Note:** `AdministratorAccess` gives full access to all AWS services. This is fine for a personal lab account. In a production environment, you would create a custom policy with only the permissions needed for the job.

13. Click **Next**.
14. Review the details. Confirm the username and that `AdministratorAccess` is listed under Permissions summary.
15. Click **Create user**.

You should see a green banner saying **User created successfully**. The page will show a **Console sign-in URL** - save this URL. It looks like `https://123456789012.signin.aws.amazon.com/console`. This is your IAM login page. Bookmark it.

---

## 3. Generate Access Keys

Access keys let the AWS CLI authenticate as your IAM user. You need an Access Key ID and a Secret Access Key.

**In the AWS Console** (IAM > Users > Your User > Security credentials):

1. Log out of the root account. Go to your IAM sign-in URL (the one you just saved) and log in with your IAM username and password.
2. In the top search bar, type `IAM` and click **IAM**.
3. In the left sidebar, click **Users**.
4. Click on your IAM username (for example: `dba-admin`).
5. Click the **Security credentials** tab.
6. Scroll down to the **Access keys** section.
7. Click **Create access key**.
8. On the next page, select **Command Line Interface (CLI)**.
9. Check the acknowledgment box at the bottom.
10. Click **Next**.
11. Optionally add a description tag like `lab-cli`. Click **Create access key**.
12. You will see your **Access key ID** (starts with `AKIA`) and **Secret access key**.

> **Critical:** This is the only time AWS will show you the Secret Access Key. If you close this page without copying it, you cannot retrieve it - you would have to delete the key and create a new one.

13. Copy both values and paste them somewhere safe temporarily. You will use them in Section 5.
14. Click **Done**.

---

## 4. Install the AWS CLI v2

The AWS CLI is the primary tool you will use to interact with AWS from your terminal throughout this entire training track.

### Step 1: Check if the CLI is already installed

**In your terminal** (local machine):

```bash
aws --version
```

Expected output (yours will differ):
```
aws-cli/2.27.1 Python/3.12.4 Darwin/24.6.0 exe/x86_64 prompt/off
```

If you see a version number starting with `2.x`, skip to Section 5. If you see `command not found` or a version starting with `1.x`, continue below.

### Step 2: Download and install

**On macOS:**

**In your terminal** (local machine):

```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "/tmp/AWSCLIV2.pkg"
```

- `curl` - downloads a file from a URL
- `-o "/tmp/AWSCLIV2.pkg"` - saves the downloaded file to your /tmp directory

**In your terminal** (local machine):

```bash
sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
```

- `sudo` - runs the command as root (required to install to system directories)
- `installer` - the macOS package installer
- `-pkg` - specifies the package file
- `-target /` - installs to the root filesystem

**On Windows:**

**In your browser:**

1. Download the installer from: https://awscli.amazonaws.com/AWSCLIV2.msi
2. Run the downloaded `.msi` file.
3. Click through the installer, accepting defaults.
4. Close and reopen PowerShell after installation.

**On Linux (x86_64):**

**In your terminal** (local machine):

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
```

**In your terminal** (local machine):

```bash
cd /tmp
```

**In your terminal** (local machine):

```bash
unzip awscliv2.zip
```

**In your terminal** (local machine):

```bash
sudo ./aws/install
```

### Step 3: Verify the installation

**In your terminal** (local machine):

```bash
aws --version
```

Expected output (yours will differ):
```
aws-cli/2.27.1 Python/3.12.4 Darwin/24.6.0 exe/x86_64 prompt/off
```

If you see a `2.x` version, you are good to go.

---

## 5. Configure the AWS CLI

Now you connect the CLI to your AWS account using the access keys from Section 3.

**In your terminal** (local machine):

```bash
aws configure
```

This launches an interactive prompt. Enter your details when asked:

```
AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name [None]: us-east-1
Default output format [None]: json
```

What each prompt means:
- **Access Key ID** - the public part of your IAM credentials (starts with `AKIA`). Paste the one you copied in Section 3.
- **Secret Access Key** - the private part. Treat this like a password. Never share it or commit it to Git.
- **Default region name** - the AWS region your commands will target. Use the region closest to you. Common choices: `us-east-1` (Virginia), `us-west-2` (Oregon), `eu-west-1` (Ireland), `af-south-1` (Cape Town).
- **Default output format** - use `json`. Other options are `text` and `table`.

The CLI stores these values in two files on your machine:
- `~/.aws/credentials` - stores the access keys
- `~/.aws/config` - stores the region and output format

---

## 6. Verify: aws sts get-caller-identity

This is the moment of truth. Run the following command to confirm the CLI is authenticated and pointing to your account.

**In your terminal** (local machine):

```bash
aws sts get-caller-identity
```

- `sts` - the Security Token Service, used for identity verification
- `get-caller-identity` - returns the identity (account, user, ARN) of whoever is making the call

Expected output (yours will differ):
```json
{
    "UserId": "AIDAIOSFODNN7EXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/dba-admin"
}
```

Verify that:
- The `Account` field shows your 12-digit AWS account ID
- The `Arn` field shows your IAM username (not `root`)

If you get an error like `An error occurred (InvalidClientTokenId)`, your access key is wrong. Run `aws configure` again and re-enter your keys carefully.

---

## 7. Set Up MFA on the Root Account

Multi-Factor Authentication (MFA) adds a second layer of security to your root account. Even if someone gets your root password, they cannot log in without the MFA code from your phone.

This is not optional in any professional setting. Set it up now while you are thinking about it.

**In the AWS Console** (logged in as root, not your IAM user):

1. Log out of your IAM user session.
2. Go to [https://console.aws.amazon.com](https://console.aws.amazon.com) and log in with your **root** email and password.
3. Click your account name in the top-right corner.
4. Click **Security credentials** from the dropdown.
5. Scroll down to the **Multi-factor authentication (MFA)** section.
6. Click **Assign MFA device**.
7. Enter a device name (for example: `root-phone`).
8. Select **Authenticator app** and click **Next**.
9. Open your authenticator app on your phone (Google Authenticator, Authy, 1Password, or similar).
10. Scan the QR code shown on screen. Your authenticator app will start generating 6-digit codes.
11. Enter two consecutive MFA codes from your app into the two input fields. Wait for the first code to expire and a new one to appear before entering the second code.
12. Click **Add MFA**.

You should see a green banner confirming MFA is enabled. From now on, logging into the root account requires both a password and an MFA code.

> **Tip:** Also enable MFA on your IAM user for extra security. Follow the same steps but log in as your IAM user and go to IAM > Users > your user > Security credentials > MFA.

---

## Summary

- The AWS root user has unlimited power. Never use it for daily work.
- Create an IAM user with `AdministratorAccess` for all lab activities.
- Access keys (Access Key ID + Secret Access Key) authenticate the CLI. Never share or commit them.
- The AWS CLI v2 is installed via a platform-specific package and configured with `aws configure`.
- `aws sts get-caller-identity` is your go-to command for verifying CLI authentication.
- MFA on the root account is a non-negotiable security step.

**Next:** [Guide 02 - VPC Networking Basics](./02-vpc-networking-basics.md)
