/**
 * MotorEast Receipt Portal - Supabase Integration
 *
 * This file shows how to integrate Supabase into your React app.
 * Copy relevant sections into your index.html or create a separate JS file.
 */

// ============================================
// 1. INITIALIZE SUPABASE CLIENT
// ============================================

// Add this script tag to your HTML head:
// <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>

// Initialize the client
const SUPABASE_URL = 'https://your-project.supabase.co'; // Replace with your URL
const SUPABASE_ANON_KEY = 'your-anon-key-here'; // Replace with your anon key

const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ============================================
// 2. AUTHENTICATION FUNCTIONS
// ============================================

const auth = {
    // Sign up new user
    async signUp(email, password, metadata) {
        const { data, error } = await supabase.auth.signUp({
            email,
            password,
            options: {
                data: {
                    name: metadata.name,
                    vehicle_number: metadata.vehicle,
                    // Note: condo_id should be set separately after signup
                }
            }
        });
        if (error) throw error;
        return data;
    },

    // Sign in existing user
    async signIn(email, password) {
        const { data, error } = await supabase.auth.signInWithPassword({
            email,
            password
        });
        if (error) throw error;
        return data;
    },

    // Sign out
    async signOut() {
        const { error } = await supabase.auth.signOut();
        if (error) throw error;
    },

    // Get current user
    async getCurrentUser() {
        const { data: { user } } = await supabase.auth.getUser();
        return user;
    },

    // Get user profile with condo info
    async getUserProfile(userId) {
        const { data, error } = await supabase
            .from('profiles')
            .select(`
                *,
                condo:condos(*)
            `)
            .eq('id', userId)
            .single();
        if (error) throw error;
        return data;
    },

    // Listen for auth state changes
    onAuthStateChange(callback) {
        return supabase.auth.onAuthStateChange((event, session) => {
            callback(event, session);
        });
    }
};

// ============================================
// 3. CLAIMS FUNCTIONS
// ============================================

const claims = {
    // Submit a new claim
    async submitClaim(claimData, receiptFile) {
        const user = await auth.getCurrentUser();
        if (!user) throw new Error('Not authenticated');

        // Get user profile for condo info
        const profile = await auth.getUserProfile(user.id);

        // Upload receipt image
        let receiptPath = null;
        if (receiptFile) {
            const fileName = `${user.id}/${Date.now()}-${receiptFile.name}`;
            const { data: uploadData, error: uploadError } = await supabase.storage
                .from('receipts')
                .upload(fileName, receiptFile);
            if (uploadError) throw uploadError;
            receiptPath = uploadData.path;
        }

        // Calculate rebate
        const rebateAmount = claimData.amount * profile.condo.rebate_rate;

        // Insert claim
        const { data, error } = await supabase
            .from('claims')
            .insert({
                user_id: user.id,
                condo_id: profile.condo_id,
                charge_date: claimData.date,
                operator: claimData.operator,
                amount: claimData.amount,
                receipt_image_path: receiptPath,
                rebate_rate: profile.condo.rebate_rate,
                rebate_amount: rebateAmount,
                status: claimData.amount > 300 ? 'flagged' : 'pending'
            })
            .select()
            .single();

        if (error) throw error;
        return data;
    },

    // Get user's claims
    async getUserClaims(userId) {
        const { data, error } = await supabase
            .from('claims')
            .select(`
                *,
                condo:condos(name, tier)
            `)
            .eq('user_id', userId)
            .order('charge_date', { ascending: false });
        if (error) throw error;
        return data;
    },

    // Get all claims (admin)
    async getAllClaims(filters = {}) {
        let query = supabase
            .from('claims_with_details')
            .select('*')
            .order('created_at', { ascending: false });

        if (filters.status && filters.status !== 'all') {
            query = query.eq('status', filters.status);
        }
        if (filters.condo) {
            query = query.eq('condo_name', filters.condo);
        }

        const { data, error } = await query;
        if (error) throw error;
        return data;
    },

    // Approve/reject claim (admin)
    async updateClaimStatus(claimId, status, reason = null) {
        const user = await auth.getCurrentUser();
        const { data, error } = await supabase
            .from('claims')
            .update({
                status,
                reviewed_by: user.id,
                reviewed_at: new Date().toISOString(),
                rejection_reason: reason
            })
            .eq('id', claimId)
            .select()
            .single();
        if (error) throw error;
        return data;
    },

    // Get monthly summary for user
    async getMonthlySummary(userId) {
        const { data, error } = await supabase
            .from('monthly_rebate_summary')
            .select('*')
            .eq('user_id', userId)
            .order('month_year', { ascending: false });
        if (error) throw error;
        return data;
    },

    // Get YTD rebate for user
    async getYTDRebate(userId) {
        const currentYear = new Date().getFullYear();
        const { data, error } = await supabase
            .from('claims')
            .select('rebate_amount')
            .eq('user_id', userId)
            .eq('status', 'approved')
            .gte('charge_date', `${currentYear}-01-01`);
        if (error) throw error;
        return data.reduce((sum, c) => sum + parseFloat(c.rebate_amount), 0);
    }
};

// ============================================
// 4. CONDO FUNCTIONS
// ============================================

const condos = {
    // Get all condos
    async getAll() {
        const { data, error } = await supabase
            .from('condos')
            .select('*')
            .order('name');
        if (error) throw error;
        return data;
    },

    // Get condo stats
    async getStats() {
        const { data, error } = await supabase
            .from('condo_stats')
            .select('*');
        if (error) throw error;
        return data;
    }
};

// ============================================
// 5. ADMIN FUNCTIONS
// ============================================

const admin = {
    // Get pending registrations
    async getPendingRegistrations() {
        const { data, error } = await supabase
            .from('pending_registrations')
            .select(`
                *,
                condo:condos(name, tier)
            `)
            .eq('status', 'pending')
            .order('created_at', { ascending: false });
        if (error) throw error;
        return data;
    },

    // Approve registration
    async approveRegistration(registrationId) {
        // This would typically be a server-side function
        // For now, update the status
        const { data, error } = await supabase
            .from('pending_registrations')
            .update({
                status: 'approved',
                reviewed_at: new Date().toISOString()
            })
            .eq('id', registrationId)
            .select()
            .single();
        if (error) throw error;
        return data;
    },

    // Export claims to CSV
    async exportClaimsCSV(filters = {}) {
        const claimsData = await claims.getAllClaims(filters);

        const headers = ['Date', 'Participant', 'Condo', 'Vehicle', 'Operator', 'Amount', 'Rebate Rate', 'Rebate Amount', 'Status'];
        const rows = claimsData.map(c => [
            c.charge_date,
            c.participant_name,
            c.condo_name,
            c.vehicle_number,
            c.operator,
            c.amount,
            `${(c.rebate_rate * 100).toFixed(0)}%`,
            c.rebate_amount,
            c.status
        ]);

        const csvContent = [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
        return csvContent;
    },

    // Get dashboard stats
    async getDashboardStats() {
        const { data: claimsData } = await supabase
            .from('claims')
            .select('status, rebate_amount');

        return {
            pending: claimsData.filter(c => c.status === 'pending').length,
            flagged: claimsData.filter(c => c.status === 'flagged').length,
            approved: claimsData.filter(c => c.status === 'approved').length,
            totalPayout: claimsData
                .filter(c => c.status === 'approved')
                .reduce((sum, c) => sum + parseFloat(c.rebate_amount), 0)
        };
    }
};

// ============================================
// 6. STORAGE FUNCTIONS
// ============================================

const storage = {
    // Get receipt image URL
    async getReceiptUrl(path) {
        if (!path) return null;
        const { data } = supabase.storage
            .from('receipts')
            .getPublicUrl(path);
        return data.publicUrl;
    },

    // Upload receipt
    async uploadReceipt(userId, file) {
        const fileName = `${userId}/${Date.now()}-${file.name}`;
        const { data, error } = await supabase.storage
            .from('receipts')
            .upload(fileName, file);
        if (error) throw error;
        return data.path;
    }
};

// ============================================
// 7. REACT INTEGRATION EXAMPLE
// ============================================

/*
// In your React component, use like this:

function App() {
    const [user, setUser] = useState(null);
    const [profile, setProfile] = useState(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        // Check initial auth state
        auth.getCurrentUser().then(async (user) => {
            if (user) {
                setUser(user);
                const profile = await auth.getUserProfile(user.id);
                setProfile(profile);
            }
            setLoading(false);
        });

        // Listen for auth changes
        const { data: { subscription } } = auth.onAuthStateChange(async (event, session) => {
            if (event === 'SIGNED_IN' && session?.user) {
                setUser(session.user);
                const profile = await auth.getUserProfile(session.user.id);
                setProfile(profile);
            } else if (event === 'SIGNED_OUT') {
                setUser(null);
                setProfile(null);
            }
        });

        return () => subscription.unsubscribe();
    }, []);

    const handleLogin = async (email, password) => {
        try {
            await auth.signIn(email, password);
            // Auth state change listener will handle the rest
        } catch (error) {
            console.error('Login failed:', error.message);
        }
    };

    const handleSubmitClaim = async (formData, receiptFile) => {
        try {
            const newClaim = await claims.submitClaim(formData, receiptFile);
            // Refresh claims list
        } catch (error) {
            console.error('Claim submission failed:', error.message);
        }
    };

    // ... rest of your component
}
*/

// Export for use
window.MotorEastDB = {
    supabase,
    auth,
    claims,
    condos,
    admin,
    storage
};
