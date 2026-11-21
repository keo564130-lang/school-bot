-- Миграция: добавление настроек приватности
-- Выполнить в Supabase SQL Editor для существующих баз данных

alter table public.profiles 
add column if not exists privacy_messages text default 'everyone' 
check (privacy_messages in ('everyone', 'request'));

comment on column public.profiles.privacy_messages is 'Настройки приватности сообщений: everyone = все могут писать, request = только по запросу';
