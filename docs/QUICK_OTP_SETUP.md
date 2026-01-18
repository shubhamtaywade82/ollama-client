# Quick OTP Setup for Automated Releases

## What You Need

Your GitHub repository needs **two secrets** for automated gem releases with MFA:

1. **RUBYGEMS_API_KEY** - Your RubyGems API key
2. **RUBYGEMS_OTP_SECRET** - Your RubyGems OTP secret

## Step 1: Get Your OTP Secret

1. Log in to https://rubygems.org
2. Go to **Edit Profile** → **Multi-factor Authentication**
3. Copy the **secret key** (long alphanumeric string like `JBSWY3DPEHPK3PXP`)

**⚠️ Save this securely!** If you don't see it, you may need to regenerate your MFA.

## Step 2: Add Secrets to GitHub

1. Go to your GitHub repo: https://github.com/shubhamtaywade82/ollama-client
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Add two secrets:

| Secret Name           | Value           | Where to Get It                       |
| --------------------- | --------------- | ------------------------------------- |
| `RUBYGEMS_API_KEY`    | Your API key    | https://rubygems.org/profile/api_keys |
| `RUBYGEMS_OTP_SECRET` | Your OTP secret | RubyGems MFA settings (Step 1)        |

## Step 3: Test It

```bash
# Bump version in lib/ollama/version.rb
# Then create and push tag:
git tag v0.2.4
git push origin v0.2.4
```

The GitHub Action will automatically:
- Generate OTP code
- Build gem
- Push to RubyGems with OTP authentication

## Test OTP Locally (Optional)

```bash
gem install rotp
ruby -r rotp -e "puts ROTP::TOTP.new('YOUR_SECRET_HERE').now"
```

This should match the code in your authenticator app.

## Troubleshooting

### "Invalid OTP code"
- Verify `RUBYGEMS_OTP_SECRET` is correct
- Check it matches your authenticator app

### "unauthorized"
- Verify `RUBYGEMS_API_KEY` is correct
- Create new API key with push permissions

### Need more help?
See full guide: `docs/RUBYGEMS_OTP_SETUP.md`

## How It Works

```yaml
- name: Install OTP generator
  run: gem install rotp

- name: Publish gem with OTP
  env:
    GEM_HOST_API_KEY: ${{ secrets.RUBYGEMS_API_KEY }}
    RUBYGEMS_OTP_SECRET: ${{ secrets.RUBYGEMS_OTP_SECRET }}
  run: |
    otp_code=$(ruby -r rotp -e "puts ROTP::TOTP.new(ENV['RUBYGEMS_OTP_SECRET']).now")
    gem push "ollama-client-${version}.gem" --otp "$otp_code"
```

That's it! Your automated releases are now secured with MFA. 🔒
