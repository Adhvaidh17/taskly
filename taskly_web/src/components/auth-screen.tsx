'use client';

import { useState } from 'react';
import { LockKeyhole, Mail, MessageSquareText, Phone, Sparkles } from 'lucide-react';
import { useTaskly } from '@/lib/taskly-store';

export function AuthScreen() {
  const { supabase } = useTaskly();
  const [mode, setMode] = useState<'password' | 'emailOtp' | 'phoneOtp'>('password');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [phone, setPhone] = useState('');
  const [otp, setOtp] = useState('');
  const [sent, setSent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setBusy(true); setError(null);
    try {
      if (mode === 'password') {
        const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
        if (error) throw error;
      } else if (mode === 'emailOtp') {
        if (!sent) {
          const { error } = await supabase.auth.signInWithOtp({ email: email.trim(), options: { shouldCreateUser: false } });
          if (error) throw error;
          setSent(true);
        } else {
          const { error } = await supabase.auth.verifyOtp({ email: email.trim(), token: otp.trim(), type: 'email' });
          if (error) throw error;
        }
      } else if (!sent) {
        const { error } = await supabase.auth.signInWithOtp({ phone: phone.trim(), options: { shouldCreateUser: false } });
        if (error) throw error;
        setSent(true);
      } else {
        const { error } = await supabase.auth.verifyOtp({ phone: phone.trim(), token: otp.trim(), type: 'sms' });
        if (error) throw error;
      }
    } catch (e) { setError(String(e)); }
    finally { setBusy(false); }
  }

  return (
    <main className="auth-page">
      <section className="auth-hero">
        <div className="auth-brand"><img src="/taskly-logo.svg" alt="Taskly" /><span>Taskly</span></div>
        <div className="auth-hero-copy">
          <span className="eyebrow"><Sparkles size={15} /> Work that moves with your conversations</span>
          <h1>Chats become tasks.<br />Tasks become progress.</h1>
          <p>The desktop companion for the same Taskly account, groups, tasks and files used on your phone.</p>
        </div>
        <div className="auth-visual">
          <div className="mini-chat"><MessageSquareText size={18} /><div><b>Priya</b><span>Send the revised proposal by 4 PM</span></div></div>
          <div className="mini-task"><span className="mini-check">✓</span><div><b>Revised proposal</b><span>Today · 4:00 PM</span></div></div>
        </div>
      </section>
      <section className="auth-card-wrap">
        <div className="auth-card">
          <div><h2>Sign in to Taskly</h2><p>Use the same account as your mobile app.</p></div>
          <div className="auth-tabs">
            <button className={mode === 'password' ? 'active' : ''} onClick={() => { setMode('password'); setSent(false); }}>Password</button>
            <button className={mode === 'emailOtp' ? 'active' : ''} onClick={() => { setMode('emailOtp'); setSent(false); }}>Email OTP</button>
            <button className={mode === 'phoneOtp' ? 'active' : ''} onClick={() => { setMode('phoneOtp'); setSent(false); }}>Phone OTP</button>
          </div>
          {mode !== 'phoneOtp' ? (
            <label className="field"><span>Email</span><div className="input-shell"><Mail size={17} /><input value={email} onChange={(e) => setEmail(e.target.value)} type="email" placeholder="you@company.com" /></div></label>
          ) : (
            <label className="field"><span>Phone</span><div className="input-shell"><Phone size={17} /><input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="+91 90000 00000" /></div></label>
          )}
          {mode === 'password' ? (
            <label className="field"><span>Password</span><div className="input-shell"><LockKeyhole size={17} /><input value={password} onChange={(e) => setPassword(e.target.value)} type="password" placeholder="Your password" onKeyDown={(e) => { if (e.key === 'Enter') void submit(); }} /></div></label>
          ) : sent ? (
            <label className="field"><span>Verification code</span><div className="input-shell"><LockKeyhole size={17} /><input value={otp} onChange={(e) => setOtp(e.target.value)} inputMode="numeric" placeholder="6-digit code" onKeyDown={(e) => { if (e.key === 'Enter') void submit(); }} /></div></label>
          ) : null}
          {error ? <div className="error-box">{error}</div> : null}
          <button className="primary-button auth-submit" disabled={busy} onClick={() => void submit()}>{busy ? 'Please wait…' : mode === 'password' ? 'Sign in' : sent ? 'Verify and sign in' : 'Send code'}</button>
          <p className="auth-note">Taskly Web uses your existing Supabase account. It does not create a second copy of your chats or tasks.</p>
        </div>
      </section>
    </main>
  );
}
