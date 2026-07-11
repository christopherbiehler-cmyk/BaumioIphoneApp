// Supabase Edge Function: Konto-Löschung (Apple-Pflicht, Guideline 5.1.1v)
//
// Die App ruft diese Funktion mit dem Access-Token des angemeldeten Nutzers auf.
// Wir ermitteln den Nutzer aus dem JWT und löschen mit dem Service-Role-Key
// sein Profil (Cascade auf alle Projektdaten) und den Auth-Account.
//
// Deploy:  supabase functions deploy delete-account
//   (oder im Dashboard → Edge Functions → Create → Code einfügen → Deploy)

import { createClient } from 'jsr:@supabase/supabase-js@2'

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 })
  }

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return new Response(JSON.stringify({ error: 'Nicht angemeldet' }), { status: 401 })
  }

  const url = Deno.env.get('SUPABASE_URL')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  // Nutzer sicher aus dem übergebenen JWT bestimmen.
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data: { user }, error: userError } = await userClient.auth.getUser()
  if (userError || !user) {
    return new Response(JSON.stringify({ error: 'Ungültige Sitzung' }), { status: 401 })
  }

  // Mit Service-Role löschen (umgeht RLS).
  const admin = createClient(url, serviceKey)

  // Profil löschen – per ON DELETE CASCADE hängen alle Projektdaten daran.
  await admin.from('profiles').delete().eq('id', user.id)

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id)
  if (deleteError) {
    console.error('Löschen fehlgeschlagen:', deleteError.message)
    return new Response(JSON.stringify({ error: 'Löschen fehlgeschlagen' }), { status: 500 })
  }

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
})
