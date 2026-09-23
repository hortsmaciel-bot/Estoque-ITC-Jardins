// ============================================================
// Conexão com o Supabase — preencha com os dados do SEU projeto.
// Supabase → Project Settings → API (ou "Data API" / "API Keys"):
//   • Project URL
//   • chave "anon public" (ou "publishable", que começa com sb_publishable_)
// Estas duas informações são públicas por natureza: quem protege os dados
// é o login + as regras de acesso (RLS) criadas pelo configurar-banco.sql.
// NUNCA coloque aqui a chave "service_role" / "secret".
// ============================================================
window.ITC_CONFIG = {
  supabaseUrl: "https://aqxncnxihpxbmdwycapg.supabase.co",
  supabaseAnonKey: "sb_publishable_7A847ar_yQRfBQU3oIFZpA_36uM8lLB"
};
