-- Run once in the BOOM JEJU Supabase SQL Editor to enable inquiry deletion.
-- Only approved superadmins can delete private customer inquiries.
drop policy if exists boom_inquiries_staff_delete on public.boom_inquiries;
create policy boom_inquiries_staff_delete on public.boom_inquiries
for delete to authenticated
using (
  exists (
    select 1 from public.staff_profiles sp
    where sp.user_id = auth.uid()
      and sp.approved = true
      and sp.is_superadmin = true
  )
);
grant delete on public.boom_inquiries to authenticated;
