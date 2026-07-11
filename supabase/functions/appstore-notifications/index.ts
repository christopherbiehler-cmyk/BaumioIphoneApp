// Supabase Edge Function: App Store Server Notifications V2
//
// Apple ruft diese URL bei Abo-Ereignissen (Kauf, Verlängerung, Ablauf, Erstattung …) auf.
// Die Funktion liest den signierten Payload, ermittelt den Nutzer über `appAccountToken`
// (= Supabase-User-ID, die die App beim Kauf mitgibt) und setzt `profiles.is_pro`
// serverseitig – damit ist der Pro-Status manipulationssicher.
//
// Deploy:  supabase functions deploy appstore-notifications --no-verify-jwt
// URL dann in App Store Connect als „Production/Sandbox Server URL" eintragen.
//
// Hinweis: SUPABASE_URL und SUPABASE_SERVICE_ROLE_KEY werden von Supabase automatisch
// als Secrets bereitgestellt.

interface DecodedTransaction {
  appAccountToken?: string;
  productId?: string;
  expiresDate?: number; // ms seit 1970
}

interface DecodedNotification {
  notificationType?: string;
  subtype?: string;
  data?: {
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
}

/** Dekodiert den Payload-Teil eines JWS (ohne Signaturprüfung). */
function decodeJwsPayload<T>(jws: string): T {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("Ungültiges JWS-Format");
  let base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
  while (base64.length % 4 !== 0) base64 += "=";
  const json = atob(base64);
  return JSON.parse(json) as T;
}

/** Ableitung des Pro-Status aus Benachrichtigungstyp + Ablaufdatum. */
function isProActive(type: string | undefined, expiresDate: number | undefined): boolean {
  const inactiveTypes = ["EXPIRED", "REFUND", "REVOKE", "GRACE_PERIOD_EXPIRED"];
  if (type && inactiveTypes.includes(type)) return false;
  if (expiresDate) return expiresDate > Date.now();
  return true;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  try {
    const body = await req.json();
    const signedPayload: string | undefined = body?.signedPayload;
    if (!signedPayload) {
      return new Response("Missing signedPayload", { status: 400 });
    }

    const notification = decodeJwsPayload<DecodedNotification>(signedPayload);
    const signedTransaction = notification.data?.signedTransactionInfo;
    if (!signedTransaction) {
      // Manche Ereignisse (z. B. Tests) enthalten keine Transaktion – einfach bestätigen.
      return new Response("OK (keine Transaktion)", { status: 200 });
    }

    const transaction = decodeJwsPayload<DecodedTransaction>(signedTransaction);
    const userId = transaction.appAccountToken;
    if (!userId) {
      // Ohne appAccountToken keine Zuordnung möglich.
      return new Response("OK (kein appAccountToken)", { status: 200 });
    }

    const active = isProActive(notification.notificationType, transaction.expiresDate);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const res = await fetch(
      `${supabaseUrl}/rest/v1/profiles?id=eq.${userId}`,
      {
        method: "PATCH",
        headers: {
          "apikey": serviceKey,
          "Authorization": `Bearer ${serviceKey}`,
          "Content-Type": "application/json",
          "Prefer": "return=minimal",
        },
        body: JSON.stringify({
          // Gleiche Spalte wie Website/Stripe: 'pro' bei aktivem Abo, sonst 'free'.
          plan: active ? "pro" : "free",
          updated_at: new Date().toISOString(),
        }),
      },
    );

    if (!res.ok) {
      const text = await res.text();
      console.error("Supabase-Update fehlgeschlagen:", res.status, text);
      return new Response("Supabase update failed", { status: 500 });
    }

    return new Response("OK", { status: 200 });
  } catch (error) {
    console.error("Fehler bei der Verarbeitung:", error);
    return new Response("Bad Request", { status: 400 });
  }
});
