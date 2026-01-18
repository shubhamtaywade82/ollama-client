# How to Get Your RubyGems OTP Secret

## The Problem

You need the **OTP secret key** from RubyGems, not the 6-digit codes from your authenticator app.

## What It Looks Like

```
Example: JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP

✅ Valid format:
- All UPPERCASE letters A-Z
- Numbers 2-7 only
- Usually 16-32 characters
- No spaces, dashes, underscores, or special characters

❌ This is NOT it:
- 123456 (that's the OTP code, not the secret)
- abc123_secret (contains invalid characters)
- YOUR_SECRET_HERE (that's a placeholder!)
```

## Step-by-Step: Get Your Secret

### Method 1: Find Existing Secret (If Saved)

When you first enabled MFA on RubyGems, it showed you a QR code and a secret key. If you saved that secret key, use it!

Check these places:
- Password manager (1Password, LastPass, Bitwarden, etc.)
- Notes app
- Screenshot of the QR code setup page

### Method 2: Regenerate MFA on RubyGems

If you can't find the original secret, regenerate it:

#### Step 1: Log in to RubyGems
Go to https://rubygems.org

#### Step 2: Go to MFA Settings
1. Click your profile picture/name (top right)
2. Click **Edit Profile**
3. Click **Multi-factor Authentication** (left sidebar)

#### Step 3: Regenerate MFA
1. Click **"Disable Multi-factor Authentication"**
2. Confirm disabling
3. Click **"Enable Multi-factor Authentication"** again
4. You'll see a QR code and the **secret key** text

#### Step 4: Save the Secret
```
IMPORTANT: Copy the secret key NOW!
Example: JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP
```

#### Step 5: Update Your Authenticator App
1. Remove the old RubyGems entry from your authenticator app
2. Scan the new QR code
3. Enter the 6-digit code to verify

⚠️ **Warning:** After regenerating, your old authenticator codes won't work!

## Test Your Secret

Once you have the secret, test it:

```bash
# Replace JBSWY... with YOUR actual secret
ruby -r rotp -e "puts ROTP::TOTP.new('JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP').now"
```

**Expected output:**
```
123456  ← A 6-digit number
```

**This number should match** your authenticator app at the same time!

## Common Mistakes

### ❌ Using the 6-digit OTP code
```bash
# WRONG - This is the code, not the secret
ruby -r rotp -e "puts ROTP::TOTP.new('123456').now"
# Error: Invalid Base32 Character
```

### ❌ Using the placeholder text
```bash
# WRONG - This is the example placeholder
ruby -r rotp -e "puts ROTP::TOTP.new('YOUR_SECRET_HERE').now"
# Error: Invalid Base32 Character - '_'
```

### ✅ Using the actual secret
```bash
# CORRECT - Your actual Base32 secret from RubyGems
ruby -r rotp -e "puts ROTP::TOTP.new('JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP').now"
# Output: 123456
```

## Where to Use It

Once you have your real secret:

### 1. Test Locally
```bash
ruby -r rotp -e "puts ROTP::TOTP.new('YOUR_ACTUAL_SECRET').now"
```

### 2. Add to GitHub Secrets
1. Go to: https://github.com/YOUR_USERNAME/YOUR_REPO/settings/secrets/actions
2. Click **New repository secret**
3. Name: `RUBYGEMS_OTP_SECRET`
4. Value: Your actual secret (e.g., `JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP`)
5. Click **Add secret**

## Still Having Issues?

### Error: "Invalid Base32 Character"

Your secret contains invalid characters. Check:
- No underscores (`_`)
- No lowercase letters
- No numbers 0, 1, 8, 9
- No spaces or special characters

Valid characters: `A-Z` and `2-7` only

### Error: "OTP code doesn't match"

1. Make sure your computer's time is synchronized
2. Try again (codes change every 30 seconds)
3. Verify the secret is correct

### Can't Find Secret Anywhere

You'll need to regenerate MFA (see Method 2 above).

## Security Note

🔒 **Keep your OTP secret secure!**
- Don't share it publicly
- Don't commit it to git
- Store it in a password manager
- Only add it to GitHub Secrets (which are encrypted)

The secret is like a password - anyone with it can generate your OTP codes!
