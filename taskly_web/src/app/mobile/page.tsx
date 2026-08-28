import { Monitor, Smartphone } from 'lucide-react';

export default function MobilePage() {
  return <main className="mobile-block-page"><div className="mobile-block-card"><img src="/taskly-logo.svg" alt="Taskly" /><h1>Taskly Web is for desktop</h1><p>Open <strong>taskly.madrascreatives.com</strong> on a computer or use the Taskly app on your phone.</p><div className="device-illustration"><Smartphone size={32} /><span>+</span><Monitor size={42} /></div></div></main>;
}
