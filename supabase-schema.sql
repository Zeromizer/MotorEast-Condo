-- MotorEast EV-Ready Condo Rebate Portal
-- Supabase Database Schema
-- Run this in Supabase SQL Editor

-- ============================================
-- 1. CONDOS TABLE
-- ============================================
CREATE TABLE condos (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    tier TEXT NOT NULL CHECK (tier IN ('Bronze', 'Silver', 'Gold', 'Platinum')),
    rebate_rate DECIMAL(4,2) NOT NULL, -- e.g., 0.10 for 10%
    duration_years INTEGER NOT NULL DEFAULT 2,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert default condos
INSERT INTO condos (name, tier, rebate_rate, duration_years) VALUES
    ('The Reef @ KPE', 'Gold', 0.15, 3),
    ('Parc Esta', 'Silver', 0.12, 2),
    ('Treasure @ Tampines', 'Bronze', 0.10, 2);

-- ============================================
-- 2. PROFILES TABLE (extends Supabase auth.users)
-- ============================================
CREATE TABLE profiles (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    email TEXT NOT NULL,
    name TEXT NOT NULL,
    vehicle_number TEXT NOT NULL,
    condo_id UUID REFERENCES condos(id),
    role TEXT NOT NULL DEFAULT 'customer' CHECK (role IN ('customer', 'admin')),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
    year_cap DECIMAL(10,2) NOT NULL DEFAULT 500.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 3. PENDING REGISTRATIONS TABLE
-- ============================================
CREATE TABLE pending_registrations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    vehicle_number TEXT NOT NULL,
    condo_id UUID REFERENCES condos(id),
    password_hash TEXT NOT NULL, -- Store hashed password temporarily
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    reviewed_by UUID REFERENCES profiles(id),
    reviewed_at TIMESTAMP WITH TIME ZONE,
    rejection_reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 4. CLAIMS TABLE
-- ============================================
CREATE TABLE claims (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
    condo_id UUID REFERENCES condos(id) NOT NULL,

    -- Receipt details
    charge_date DATE NOT NULL,
    operator TEXT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    receipt_image_path TEXT, -- Storage bucket path

    -- Rebate calculation
    rebate_rate DECIMAL(4,2) NOT NULL,
    rebate_amount DECIMAL(10,2) NOT NULL,

    -- Status tracking
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'flagged')),
    reviewed_by UUID REFERENCES profiles(id),
    reviewed_at TIMESTAMP WITH TIME ZONE,
    rejection_reason TEXT,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 5. DISBURSEMENTS TABLE (for tracking payouts)
-- ============================================
CREATE TABLE disbursements (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
    month_year TEXT NOT NULL, -- Format: '2024-12'
    total_rebate DECIMAL(10,2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processed', 'paid')),
    processed_by UUID REFERENCES profiles(id),
    processed_at TIMESTAMP WITH TIME ZONE,
    bank_reference TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 6. ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================

-- Enable RLS on all tables
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE condos ENABLE ROW LEVEL SECURITY;
ALTER TABLE claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE pending_registrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE disbursements ENABLE ROW LEVEL SECURITY;

-- CONDOS: Everyone can read
CREATE POLICY "Condos are viewable by everyone"
ON condos FOR SELECT
TO authenticated
USING (true);

-- PROFILES: Users can read own, admins can read all
CREATE POLICY "Users can view own profile"
ON profiles FOR SELECT
TO authenticated
USING (auth.uid() = id);

CREATE POLICY "Admins can view all profiles"
ON profiles FOR SELECT
TO authenticated
USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "Users can update own profile"
ON profiles FOR UPDATE
TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- CLAIMS: Users can CRUD own, admins can read/update all
CREATE POLICY "Users can view own claims"
ON claims FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Admins can view all claims"
ON claims FOR SELECT
TO authenticated
USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "Users can insert own claims"
ON claims FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own pending claims"
ON claims FOR UPDATE
TO authenticated
USING (user_id = auth.uid() AND status = 'pending')
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Admins can update any claim"
ON claims FOR UPDATE
TO authenticated
USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

-- PENDING REGISTRATIONS: Only admins can view/update
CREATE POLICY "Admins can view pending registrations"
ON pending_registrations FOR SELECT
TO authenticated
USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "Anyone can insert pending registration"
ON pending_registrations FOR INSERT
TO anon
WITH CHECK (true);

CREATE POLICY "Admins can update pending registrations"
ON pending_registrations FOR UPDATE
TO authenticated
USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

-- DISBURSEMENTS: Users can view own, admins can view/update all
CREATE POLICY "Users can view own disbursements"
ON disbursements FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Admins can view all disbursements"
ON disbursements FOR SELECT
TO authenticated
USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "Admins can manage disbursements"
ON disbursements FOR ALL
TO authenticated
USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

-- ============================================
-- 7. FUNCTIONS & TRIGGERS
-- ============================================

-- Auto-create profile when user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email, name, vehicle_number, role)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'name', 'New User'),
        COALESCE(NEW.raw_user_meta_data->>'vehicle_number', ''),
        COALESCE(NEW.raw_user_meta_data->>'role', 'customer')
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Update timestamp trigger
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_claims_updated_at
    BEFORE UPDATE ON claims
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_condos_updated_at
    BEFORE UPDATE ON condos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================
-- 8. VIEWS FOR COMMON QUERIES
-- ============================================

-- User claims with condo info
CREATE VIEW claims_with_details AS
SELECT
    c.*,
    p.name AS participant_name,
    p.email AS participant_email,
    p.vehicle_number,
    co.name AS condo_name,
    co.tier AS condo_tier
FROM claims c
JOIN profiles p ON c.user_id = p.id
JOIN condos co ON c.condo_id = co.id;

-- Monthly summary per user
CREATE VIEW monthly_rebate_summary AS
SELECT
    user_id,
    TO_CHAR(charge_date, 'YYYY-MM') AS month_year,
    COUNT(*) AS claim_count,
    SUM(amount) AS total_charged,
    SUM(rebate_amount) AS total_rebate,
    SUM(CASE WHEN status = 'approved' THEN rebate_amount ELSE 0 END) AS approved_rebate
FROM claims
GROUP BY user_id, TO_CHAR(charge_date, 'YYYY-MM');

-- Condo statistics
CREATE VIEW condo_stats AS
SELECT
    co.id,
    co.name,
    co.tier,
    co.rebate_rate,
    COUNT(DISTINCT p.id) AS owner_count,
    COALESCE(SUM(c.amount), 0) AS total_charging,
    COALESCE(SUM(c.rebate_amount), 0) AS total_rebates
FROM condos co
LEFT JOIN profiles p ON p.condo_id = co.id
LEFT JOIN claims c ON c.condo_id = co.id AND c.status = 'approved'
GROUP BY co.id, co.name, co.tier, co.rebate_rate;

-- ============================================
-- 9. CREATE ADMIN USER (run after first signup)
-- ============================================
-- After you sign up with admin@motoreast.sg, run:
-- UPDATE profiles SET role = 'admin' WHERE email = 'admin@motoreast.sg';

-- ============================================
-- 10. INDEXES FOR PERFORMANCE
-- ============================================
CREATE INDEX idx_claims_user_id ON claims(user_id);
CREATE INDEX idx_claims_status ON claims(status);
CREATE INDEX idx_claims_charge_date ON claims(charge_date);
CREATE INDEX idx_profiles_condo_id ON profiles(condo_id);
CREATE INDEX idx_profiles_role ON profiles(role);
