# Estoque do Cadaver Lab — ITC Jardins (Netlify + Supabase)

O visual e as funções são os mesmos da versão no Claude. **O login (e-mail e senha) e os dados ficam no Supabase.** O Netlify só hospeda o site, que é estático: não tem build nem funções.

## Estrutura

```
itc-estoque-supabase/
├── public/                    ← ESTA é a pasta que vai para o Netlify
│   ├── index.html             aplicativo completo
│   ├── config.js              ← coloque aqui a URL e a chave do seu Supabase
│   ├── logo-claro.png / logo-escuro.png / favicon.png
│   ├── _headers               cabeçalhos de segurança (lidos pelo Netlify)
│   └── robots.txt             impede indexação no Google
├── supabase/
│   └── configurar-banco.sql   cria tabelas, regras de acesso e o estoque inicial
├── netlify.toml               (só para deploy via GitHub: publica a pasta public)
└── LEIA-ME.md
```

**Build: não há.** Não precisa rodar nenhum comando.

---

## Passo 1 — Criar e configurar o Supabase

1. Crie uma conta em supabase.com e um projeto novo (anote a senha do banco, ela não será usada pelo site).
2. **Banco de dados:** abra o arquivo `supabase/configurar-banco.sql` e troque `seu-email@exemplo.com` pelo seu e-mail e pelos e-mails da equipe (um por linha).
   No Supabase: **SQL Editor → New query**, cole o arquivo inteiro e clique **Run**.
   Isso cria:
   - a tabela `registros` (itens, eventos, compras/ajustes e listas), já com os 72 insumos atuais;
   - a tabela `equipe`: **só os e-mails dela conseguem ver ou alterar o estoque**;
   - as regras de acesso (RLS), as funções de baixa de estoque e a atualização ao vivo (Realtime).
3. **Bloquear cadastro público:** **Authentication → Sign In / Providers**: desligue **"Allow new users to sign up"**. Mantenha o provedor **Email** ligado.
4. **Criar os usuários:** **Authentication → Users → Add user → Create new user**. Informe o e-mail e a senha e marque **Auto Confirm User**. Repita para cada pessoa. O e-mail tem que ser o mesmo que está na tabela `equipe`.
5. **Endereço do site** (depois do Passo 3, quando você já tiver o link do Netlify): **Authentication → URL Configuration**
   - *Site URL*: `https://seu-site.netlify.app`
   - *Redirect URLs*: adicione o mesmo endereço.
   Isso é necessário para o link de "Esqueci minha senha" voltar ao site.

## Passo 2 — Conectar o site ao Supabase

No Supabase, vá em **Project Settings → API Keys** (ou **Data API**) e copie:
- **Project URL** (ex.: `https://abcd1234.supabase.co`)
- a chave **anon / public**, ou a **publishable** (começa com `sb_publishable_`)

Cole as duas em `public/config.js`:

```js
window.ITC_CONFIG = {
  supabaseUrl: "https://abcd1234.supabase.co",
  supabaseAnonKey: "eyJhbGciOi...  ou  sb_publishable_..."
};
```

> Essas duas informações podem ficar no site: quem protege os dados é o login somado às regras de acesso.
> **Nunca** use a chave `service_role` / `secret` no site.

## Passo 3 — Publicar no Netlify

**Jeito mais simples (arrastar e soltar):** no Netlify, **Add new site → Deploy manually** e arraste a pasta **`public`**.
Para atualizar depois, vá em **Deploys** e arraste a pasta `public` de novo.

**Pelo GitHub (opcional):** envie a pasta inteira para um repositório e importe no Netlify. O `netlify.toml` já aponta para `public`. Deixe o *Build command* vazio.

Depois do primeiro deploy, volte ao Passo 1.5 e informe o endereço do site no Supabase.

---

## Como funciona

- **Login:** cada pessoa entra com o próprio e-mail e senha, pelo Supabase Auth. A sessão fica guardada no navegador e renova sozinha. O botão **Sair** fica no topo.
- **Esqueci minha senha:** envia um link por e-mail. Ao abrir o link, a pessoa cria a nova senha na própria tela do sistema.
- **Salvamento:** cada alteração vai direto para o Supabase. O topo mostra *Salvando…*, *Salvo na nuvem · ao vivo* ou *Sem conexão — tentando salvar…*. Se a internet cair, as alterações ficam na fila e são reenviadas; o navegador avisa se você tentar fechar a página com algo pendente.
- **Ao vivo:** o que um colega altera aparece na sua tela na hora (Supabase Realtime). Sem Realtime, a página atualiza a cada 30 segundos.
- **Baixas de estoque** (eventos, entradas, perdas) são somadas no próprio banco. Duas pessoas dando baixa ao mesmo tempo não se sobrescrevem.
- **Histórico:** cada registro guarda quando e por quem foi alterado pela última vez (colunas `atualizado_em` e `atualizado_por`).
- **Backup:** *Relatórios → Backup dos dados → Baixar backup (JSON)*. No Supabase também dá para exportar a tabela `registros` em CSV (Table Editor).

## Gerenciar a equipe

| Tarefa | Onde |
|---|---|
| Adicionar pessoa | 1) *Authentication → Users → Add user* · 2) SQL Editor: `insert into public.equipe (email) values ('pessoa@email.com');` |
| Remover acesso | SQL Editor: `delete from public.equipe where email = 'pessoa@email.com';` e apague o usuário em *Authentication → Users* |
| Trocar a própria senha | Tela de login → *Esqueci minha senha* |

## Pontos de atenção

- **E-mails do Supabase:** no plano gratuito, sem um SMTP próprio, o Supabase só envia e-mails (recuperação de senha, convites) para membros da equipe da organização no Supabase, e em quantidade bem limitada. Para o "Esqueci minha senha" funcionar para todos, configure um SMTP em *Authentication → Emails → SMTP Settings* (Resend, Brevo, Gmail etc.). Criar os usuários já com senha (Passo 1.4) funciona sem SMTP.
- **Plano gratuito do Supabase:** projetos gratuitos são **pausados após cerca de 7 dias sem uso**. Os dados não se perdem, mas o site para de carregar até alguém clicar em *Restore project* no painel. O plano pago não pausa.
- A biblioteca do Supabase é carregada do CDN jsDelivr (versão fixa 2.117.1). Se a rede da clínica bloquear esse endereço, o site mostra um aviso.
- A versão no Claude e esta versão **não se sincronizam**. O estoque inicial do SQL é o de 23/09/2026. Se você alterar algo no Claude depois disso, repita a alteração aqui.

## O que mudou em relação à versão no Claude

| Recurso exclusivo do Claude | Como ficou |
|---|---|
| Banco de dados do artefato | Tabela `registros` no Supabase (Postgres) com regras de acesso (RLS) |
| Atualização ao vivo entre usuários | Supabase Realtime (com atualização a cada 30 s como reserva) |
| Acesso pelo compartilhamento do Claude | Login com e-mail e senha (Supabase Auth) + lista `equipe` |
| Downloads pela janela do Claude | Download direto pelo navegador (HTML, CSV e backup JSON) |
| Tema do app do Claude | Segue o tema claro/escuro do sistema operacional |
| Modo somente leitura | Não existe: quem está na `equipe` pode editar |
