# Supabase Setup Guide for MotorEast Receipt Portal

## Step 1: Create Supabase Account & Project

1. Go to [https://supabase.com](https://supabase.com)
2. Click **Start your project** and sign up (GitHub login recommended)
3. Click **New Project**
4. Fill in:
   - **Name**: `motoreast-rebate`
   - **Database Password**: Generate a strong password (save this!)
   - **Region**: Choose closest to Singapore (e.g., `Southeast Asia (Singapore)`)
5. Click **Create new project** and wait ~2 minutes

## Step 2: Get Your API Keys

1. In your project dashboard, go to **Settings** > **API**
2. Copy these values (you'll need them later):
   - **Project URL**: `https://xxxxx.supabase.co`
   - **anon/public key**: `eyJhbGc...` (safe to use in frontend)
   - **service_role key**: `eyJhbGc...` (keep secret, for admin only)

## Step 3: Set Up Database Schema

1. Go to **SQL Editor** in the left sidebar
2. Click **New query**
3. Copy and paste the contents of `supabase-schema.sql` (included in this repo)
4. Click **Run** to execute

## Step 4: Set Up Authentication

1. Go to **Authentication** > **Providers**
2. Ensure **Email** is enabled
3. Configure settings:
   - **Enable email confirmations**: ON (recommended for production)
   - **Enable email change confirmation**: ON
4. Go to **Authentication** > **URL Configuration**
5. Set your **Site URL**: `https://your-domain.com` (or `http://localhost:3000` for dev)

## Step 5: Set Up Storage (for Receipt Images)

1. Go to **Storage** in the left sidebar
2. Click **Create a new bucket**
3. Name it: `receipts`
4. Set **Public bucket**: OFF (private)
5. Click **Create bucket**

### Storage Policies (Run in SQL Editor):

```sql
-- Allow authenticated users to upload receipts
CREATE POLICY "Users can upload receipts"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'receipts' AND auth.uid()::text = (storage.foldername(name))[1]);

-- Allow users to view their own receipts
CREATE POLICY "Users can view own receipts"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'receipts' AND auth.uid()::text = (storage.foldername(name))[1]);

-- Allow admins to view all receipts
CREATE POLICY "Admins can view all receipts"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'receipts' AND EXISTS (
  SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
));
```

## Step 6: Environment Variables

Create a `.env` file (don't commit this to git!):

```env
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key-here
```

## Database Schema Overview

### Tables:

| Table | Purpose |
|-------|---------|
| `profiles` | Extended user info (name, vehicle, condo, role) |
| `condos` | Condo list with tier info |
| `claims` | Receipt claims submitted by users |
| `pending_registrations` | Users awaiting admin approval |

### User Roles:
- `customer` - Regular users who submit claims
- `admin` - Can approve claims, users, generate reports

## Quick Reference: Supabase Dashboard

| Section | Use For |
|---------|---------|
| **Table Editor** | View/edit data directly |
| **SQL Editor** | Run custom queries |
| **Authentication** | Manage users |
| **Storage** | Manage uploaded files |
| **Logs** | Debug issues |

## Testing Your Setup

After setup, verify:

1. **Auth works**: Try signing up a test user
2. **Database works**: Check if tables were created in Table Editor
3. **Storage works**: Try uploading a test file

## Next Steps

Once Supabase is set up:
1. Update `index.html` to use the Supabase client (see `supabase-integration.js`)
2. Replace mock data with real database calls
3. Deploy to Vercel/Netlify

## Troubleshooting

### "Permission denied" errors
- Check Row Level Security (RLS) policies
- Ensure user is authenticated

### "Invalid API key"
- Double-check you copied the full key
- Make sure you're using the anon key (not service role) in frontend

### Images not uploading
- Check storage bucket policies
- Verify file size (default limit: 50MB)
