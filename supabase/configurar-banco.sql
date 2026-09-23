-- =====================================================================
-- Estoque do Cadaver Lab — ITC Jardins · configuração do Supabase
-- Cole este arquivo inteiro no Supabase: SQL Editor → New query → Run.
-- Pode ser executado mais de uma vez sem duplicar nada.
-- =====================================================================

-- 1) Quem pode usar o sistema -----------------------------------------
-- Só e-mails cadastrados nesta tabela conseguem ler ou alterar o estoque,
-- mesmo que alguém consiga criar uma conta no Supabase.
create table if not exists public.equipe (
  email text primary key,
  nome  text,
  criado_em timestamptz not null default now()
);
alter table public.equipe enable row level security;   -- sem políticas: o site não lê nem altera esta tabela

-- >>> TROQUE pelo(s) e-mail(s) da equipe (os mesmos usados em Authentication → Users) <<<
insert into public.equipe (email, nome) values
  ('hortsmaciel@gmail.com', 'Hortencia'),('camila.godoy@ioajardins.com.br','Camila'),('drheloisasales@gmail.com','Heloisa')
on conflict (email) do nothing;

create or replace function public.is_membro()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.equipe
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
revoke all on function public.is_membro() from public, anon;
grant execute on function public.is_membro() to authenticated;

-- 2) Dados do estoque -------------------------------------------------
-- Uma linha por registro: itens (insumos e instrumentais), eventos,
-- movimentações (compras/ajustes) e listas para clientes.
create table if not exists public.registros (
  colecao        text not null check (colecao in ('items','eventos','movs','listas')),
  id             text not null check (id ~ '^[A-Za-z0-9_.~:@+-]{1,200}$'),
  dados          jsonb not null check (jsonb_typeof(dados) = 'object' and pg_column_size(dados) < 262144),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  atualizado_por uuid default auth.uid(),
  primary key (colecao, id)
);
alter table public.registros enable row level security;

drop policy if exists "equipe le"      on public.registros;
drop policy if exists "equipe insere"  on public.registros;
drop policy if exists "equipe altera"  on public.registros;
drop policy if exists "equipe exclui"  on public.registros;
create policy "equipe le"     on public.registros for select to authenticated using (public.is_membro());
create policy "equipe insere" on public.registros for insert to authenticated with check (public.is_membro());
create policy "equipe altera" on public.registros for update to authenticated using (public.is_membro()) with check (public.is_membro());
create policy "equipe exclui" on public.registros for delete to authenticated using (public.is_membro());

revoke all on public.registros from anon;
grant select, insert, update, delete on public.registros to authenticated;

-- carimba data e autor de cada alteração
create or replace function public.registros_carimbo()
returns trigger language plpgsql as $$
begin
  new.atualizado_em := now();
  new.atualizado_por := auth.uid();
  return new;
end $$;
drop trigger if exists registros_carimbo on public.registros;
create trigger registros_carimbo before update on public.registros
  for each row execute function public.registros_carimbo();

-- 3) Operações atômicas usadas pelo site ------------------------------
-- Soma/subtrai a quantidade de um item no servidor (duas baixas simultâneas não se perdem).
create or replace function public.ajustar_quantidade(p_id text, p_delta numeric)
returns void language sql security invoker set search_path = public as $$
  update public.registros
     set dados = jsonb_set(dados, '{qtd}',
                   to_jsonb(round(coalesce(nullif(dados ->> 'qtd', '')::numeric, 0) + p_delta, 3)), true)
                 || jsonb_build_object('atualizadoEm', to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD'))
   where colecao = 'items' and id = p_id;
$$;

-- Atualiza só os campos enviados de um registro, preservando o restante.
create or replace function public.mesclar_registro(p_colecao text, p_id text, p_campos jsonb)
returns void language sql security invoker set search_path = public as $$
  update public.registros
     set dados = dados || p_campos
   where colecao = p_colecao and id = p_id and jsonb_typeof(p_campos) = 'object';
$$;

revoke all on function public.ajustar_quantidade(text, numeric) from public, anon;
revoke all on function public.mesclar_registro(text, text, jsonb) from public, anon;
grant execute on function public.ajustar_quantidade(text, numeric) to authenticated;
grant execute on function public.mesclar_registro(text, text, jsonb) to authenticated;

-- 4) Atualização ao vivo entre usuários (Realtime) ---------------------
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'registros') then
    alter publication supabase_realtime add table public.registros;
  end if;
end $$;

-- 5) Estoque inicial: 72 insumos (situação em 23/09/2026) ---------------
insert into public.registros (colecao, id, dados) values
  ('items', 'i-abracadeira-de-nylon-frontec', '{"atualizadoEm": "2026-09-23", "categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Frontec", "nome": "Abraçadeira de Nylon", "obs": "1 pac aberto", "qtd": 0, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-agulha-22g-preta-medix', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Medix", "nome": "Agulha 22G (preta)", "obs": "Várias em uso", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-alcool-70-sulmar', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Sulmar", "nome": "Álcool 70", "obs": "", "qtd": 3, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-algodao-bolinha-dr-luvas', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Dr. Luvas", "nome": "Algodão bolinha", "obs": "", "qtd": 7, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-algodao-rolo-g-sem-marca', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Sem marca", "nome": "Algodão rolo G", "obs": "", "qtd": 7, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-algodao-rolo-p-sem-marca', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Sem marca", "nome": "Algodão rolo P", "obs": "", "qtd": 11, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-avental-azul-dejamaro', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Dejamaro", "nome": "Avental azul", "obs": "+1 pac aberto", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-avental-branco-descarpack', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Descarpack", "nome": "Avental branco", "obs": "", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "2030-09-01", "valorUnit": null}'::jsonb),
  ('items', 'i-avental-branco-transparente-prevemax', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Prevemax", "nome": "Avental branco/transparente", "obs": "10 uni por pac", "qtd": 18, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-bandagem-sem-marca', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Sem marca", "nome": "Bandagem", "obs": "", "qtd": 15, "referencia": "Bandagem Elástica Adesiva Flexível Coban Atadura 10cm X 4,5m", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-campo-impermeavel-azul-esteril-venkuri', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Venkuri", "nome": "Campo impermeável azul estéril", "obs": "", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "2029-06-29", "valorUnit": null}'::jsonb),
  ('items', 'i-cateter-periferico-iv-gelco-14-descarpack', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Descarpack", "nome": "Cateter periférico IV (Gelco 14)", "obs": "", "qtd": 2, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "2029-06-01", "valorUnit": null}'::jsonb),
  ('items', 'i-compressa-soft', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Soft", "nome": "Compressa", "obs": "", "qtd": 36, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "2031-02-01", "valorUnit": null}'::jsonb),
  ('items', 'i-corante-xadrez-azul-juntalider', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Juntalider", "nome": "Corante Xadrez azul", "obs": "", "qtd": 3, "referencia": "Corante Xadrez Azul 50ml Kit 3 Unidades", "tipo": "insumo", "unidade": "uni", "validade": "2028-03-01", "valorUnit": null}'::jsonb),
  ('items', 'i-corante-xadrez-vermelho-juntalider', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Juntalider", "nome": "Corante Xadrez vermelho", "obs": "", "qtd": 3, "referencia": "Corante Líquido Tek Bond Vermelho - frasco de 50 ml", "tipo": "insumo", "unidade": "uni", "validade": "2028-03-01", "valorUnit": null}'::jsonb),
  ('items', 'i-cotonete-cremer', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Cremer", "nome": "Cotonete", "obs": "1 cx aberta", "qtd": 0, "referencia": "Cotonetes Premium 120 Hastes Algodão Ultra Macio", "tipo": "insumo", "unidade": "cx", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-equipo-bioani', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Bioani", "nome": "Equipo", "obs": "", "qtd": 23, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "2028-01-31", "valorUnit": null}'::jsonb),
  ('items', 'i-equipo-completo-medix', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Medix", "nome": "Equipo completo", "obs": "+12 soltos", "qtd": 2, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "2030-04-01", "valorUnit": null}'::jsonb),
  ('items', 'i-equipo-macrogotas-descarpack', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Descarpack", "nome": "Equipo macrogotas", "obs": "", "qtd": 9, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "2029-08-01", "valorUnit": null}'::jsonb),
  ('items', 'i-esparadrapo-impermeavel-missner', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Missner", "nome": "Esparadrapo impermeável", "obs": "", "qtd": 1, "referencia": "Esparadrapo impermeável branco 10cm x 4,5m", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-esparadrapo-impermeavel-wiltex', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Wiltex", "nome": "Esparadrapo impermeável", "obs": "", "qtd": 11, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "2030-12-02", "valorUnit": null}'::jsonb),
  ('items', 'i-fio-poliglicolico-violeta-4-procare', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Procare", "nome": "Fio poliglicólico violeta 4", "obs": "+10 soltos", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "cx", "validade": "2028-10-01", "valorUnit": null}'::jsonb),
  ('items', 'i-fita-branca-p-ciex', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Ciex", "nome": "Fita branca P", "obs": "", "qtd": 10, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-fita-microporosa-cremer', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Cremer", "nome": "Fita microporosa", "obs": "", "qtd": 5, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-fralda-pacote-vitalidade', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Vitalidade", "nome": "Fralda (pacote)", "obs": "", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-galao-limpeza-sem-marca', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Sem marca", "nome": "Galão limpeza", "obs": "", "qtd": 2, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-gaze-karina', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Karina", "nome": "Gaze", "obs": "+1 aberto", "qtd": 2, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-gaze-nobre', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Nobre", "nome": "Gaze", "obs": "", "qtd": 10, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "2034-10-31", "valorUnit": null}'::jsonb),
  ('items', 'i-gel-de-cabelo-x', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "", "nome": "Gel de cabelo", "obs": "+2 em uso", "qtd": 2, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-lacres-numerados-x', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "", "nome": "Lacres numerados", "obs": "+1 aberto", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-lamina-11-advantive', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Advantive", "nome": "Lâmina 11", "obs": "", "qtd": 3, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "2026-03-01", "valorUnit": null}'::jsonb),
  ('items', 'i-lamina-11-maxicor', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Maxicor", "nome": "Lâmina 11", "obs": "", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "2030-03-01", "valorUnit": null}'::jsonb),
  ('items', 'i-lamina-11-medix', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Medix", "nome": "Lâmina 11", "obs": "", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "2030-03-01", "valorUnit": null}'::jsonb),
  ('items', 'i-lamina-11-uniqmed', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Uniqmed", "nome": "Lâmina 11", "obs": "", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "2028-01-01", "valorUnit": null}'::jsonb),
  ('items', 'i-lamina-15-advantive', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Advantive", "nome": "Lâmina 15", "obs": "", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "2028-11-30", "valorUnit": null}'::jsonb),
  ('items', 'i-lamina-15-medix', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Medix", "nome": "Lâmina 15", "obs": "", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "2030-03-01", "valorUnit": null}'::jsonb),
  ('items', 'i-lamina-22-medix', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Medix", "nome": "Lâmina 22", "obs": "", "qtd": 2, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "2029-09-01", "valorUnit": null}'::jsonb),
  ('items', 'i-lamina-22-solidor', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Solidor", "nome": "Lâmina 22", "obs": "", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "2029-12-02", "valorUnit": null}'::jsonb),
  ('items', 'i-lamina-23-advantive', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Advantive", "nome": "Lâmina 23", "obs": "", "qtd": 3, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "2029-01-31", "valorUnit": null}'::jsonb),
  ('items', 'i-lamina-23-medix', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Medix", "nome": "Lâmina 23", "obs": "", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "2030-03-31", "valorUnit": null}'::jsonb),
  ('items', 'i-lamina-de-barbear-bic', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Bic", "nome": "Lâmina de barbear", "obs": "", "qtd": 24, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-lidocaine-restylane', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Restylane", "nome": "Lidocaine", "obs": "Lotes com validade 31/10/2024 e 31/10/2025", "qtd": 3, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "2024-10-31", "valorUnit": null}'::jsonb),
  ('items', 'i-luva-g-medix', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Medix", "nome": "Luva G", "obs": "+1 aberta", "qtd": 15, "referencia": "", "tipo": "insumo", "unidade": "cx", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-luva-m-medix-e-descarpack', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Medix e Descarpack", "nome": "Luva M", "obs": "+2 abertas", "qtd": 13, "referencia": "", "tipo": "insumo", "unidade": "cx", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-luva-p-medix', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Medix", "nome": "Luva P", "obs": "+2 abertas", "qtd": 14, "referencia": "", "tipo": "insumo", "unidade": "cx", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-lysoform-sc-johnson', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "SC Johnson", "nome": "Lysoform", "obs": "", "qtd": 16, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-malha-tubular-12cm-x-15m-m-so', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "M.SÓ", "nome": "Malha tubular 12cm x 15m", "obs": "", "qtd": 4, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-manto-protetor-invol', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Invol", "nome": "Manto protetor", "obs": "", "qtd": 46, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-mascara-dejamaro', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Dejamaro", "nome": "Máscara", "obs": "+2 abertos (50 un por pac)", "qtd": 97, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-nylon-2-shalon', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Shalon", "nome": "Nylon 2", "obs": "", "qtd": 4, "referencia": "", "tipo": "insumo", "unidade": "cx", "validade": "2030-07-01", "valorUnit": null}'::jsonb),
  ('items', 'i-nylon-2-technofio', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Technofio", "nome": "Nylon 2", "obs": "", "qtd": 4, "referencia": "", "tipo": "insumo", "unidade": "cx", "validade": "2030-03-01", "valorUnit": null}'::jsonb),
  ('items', 'i-nylon-3-bc-suture', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "BC Suture", "nome": "Nylon 3", "obs": "", "qtd": 5, "referencia": "", "tipo": "insumo", "unidade": "cx", "validade": "2030-01-20", "valorUnit": null}'::jsonb),
  ('items', 'i-nylon-3-shalon', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Shalon", "nome": "Nylon 3", "obs": "", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "cx", "validade": "2029-09-01", "valorUnit": null}'::jsonb),
  ('items', 'i-nylon-3-technofio', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Technofio", "nome": "Nylon 3", "obs": "", "qtd": 4, "referencia": "", "tipo": "insumo", "unidade": "cx", "validade": "2029-11-01", "valorUnit": null}'::jsonb),
  ('items', 'i-nylon-4-procare', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Procare", "nome": "Nylon 4", "obs": "", "qtd": 5, "referencia": "", "tipo": "insumo", "unidade": "cx", "validade": "2028-11-01", "valorUnit": null}'::jsonb),
  ('items', 'i-nylon-4-technofio', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Technofio", "nome": "Nylon 4", "obs": "", "qtd": 4, "referencia": "", "tipo": "insumo", "unidade": "cx", "validade": "2029-11-01", "valorUnit": null}'::jsonb),
  ('items', 'i-oculos-de-protecao-deltaplus', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Deltaplus", "nome": "Óculos de proteção", "obs": "", "qtd": 21, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-prope-branco-dejamaro', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Dejamaro", "nome": "Propé branco", "obs": "+4 abertos", "qtd": 3, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "2028-12-05", "valorUnit": null}'::jsonb),
  ('items', 'i-prope-pequeno-x', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "", "nome": "Propé pequeno", "obs": "", "qtd": 0, "referencia": "Propé Descartável 100 Unidades TNT Branco com Elástico", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-saco-azul-sem-marca', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Sem marca", "nome": "Saco azul", "obs": "+1 aberto", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-saco-branco-sem-marca', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Sem marca", "nome": "Saco branco", "obs": "+1 aberto", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-saco-mortuario-sem-marca', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Sem marca", "nome": "Saco mortuário", "obs": "5 uni por pac; +3 un aberto", "qtd": 2, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-saco-verde-sem-marca', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Sem marca", "nome": "Saco verde", "obs": "+1 aberto", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-saco-vermelho-sem-marca', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Sem marca", "nome": "Saco vermelho", "obs": "+1 aberto", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-seringa-20-ml-sr', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "SR", "nome": "Seringa 20 mL", "obs": "", "qtd": 127, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-seringa-5-ml-sr', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "SR", "nome": "Seringa 5 mL", "obs": "", "qtd": 91, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-seringa-60-ml-sr', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "SR", "nome": "Seringa 60 mL", "obs": "", "qtd": 50, "referencia": "https://www.mercadolivre.com.br/seringa-descartavel-60ml", "tipo": "insumo", "unidade": "uni", "validade": "2031-07-01", "valorUnit": null}'::jsonb),
  ('items', 'i-sonda-pvc-embramed', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Embramed", "nome": "Sonda PVC", "obs": "+13 soltos", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "2027-12-31", "valorUnit": null}'::jsonb),
  ('items', 'i-tapete-higienico-zelara', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Zelara", "nome": "Tapete higiênico", "obs": "", "qtd": 2, "referencia": "Tapete Higiênico K9 Pet Super Absorvente 30 Unidades 80x60", "tipo": "insumo", "unidade": "pac", "validade": "2029-05-01", "valorUnit": null}'::jsonb),
  ('items', 'i-tnt-preto-sem-marca', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Sem marca", "nome": "TNT preto", "obs": "+1 aberto", "qtd": 1, "referencia": "", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb),
  ('items', 'i-touca-descartavel-talge', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Talge", "nome": "Touca descartável", "obs": "+2 abertos", "qtd": 3, "referencia": "", "tipo": "insumo", "unidade": "pac", "validade": "2030-10-31", "valorUnit": null}'::jsonb),
  ('items', 'i-vick-vaporub-vick', '{"categoria": "", "criadoEm": "2026-09-23", "ideal": null, "marca": "Vick", "nome": "Vick VapoRub", "obs": "+1 aberto", "qtd": 0, "referencia": "Vick Vaporub Unguento 100g", "tipo": "insumo", "unidade": "uni", "validade": "", "valorUnit": null}'::jsonb)
on conflict (colecao, id) do nothing;
