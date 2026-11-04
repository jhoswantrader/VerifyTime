-- VerifyTime: revisión administrativa de pagos de membresía
-- Ejecutar en Supabase SQL Editor después de revisar este archivo.
-- Solo owner/admin pueden aprobar, rechazar o marcar duplicados.
-- No concede escritura directa sobre las tablas.

CREATE OR REPLACE FUNCTION public.platform_admin_review_membership_payment(
  p_payment_id uuid,
  p_decision text,
  p_bank_paid_at timestamptz DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_payment public.membership_payments%ROWTYPE;
  v_plan public.membership_plans%ROWTYPE;
  v_subscription_id uuid;
  v_old_end timestamptz;
BEGIN
  PERFORM public.platform_admin_assert_write_access();

  IF p_decision IS NULL
     OR p_decision NOT IN ('verified', 'rejected', 'duplicate') THEN
    RAISE EXCEPTION 'Decisión de pago no válida.';
  END IF;

  SELECT *
    INTO v_payment
    FROM public.membership_payments
   WHERE id = p_payment_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se encontró la solicitud de pago.';
  END IF;

  IF v_payment.payment_status <> 'submitted' THEN
    RAISE EXCEPTION 'Este pago ya fue revisado. Estado actual: %.',
      v_payment.payment_status;
  END IF;

  IF p_decision = 'verified' THEN
    SELECT *
      INTO v_plan
      FROM public.membership_plans
     WHERE id = v_payment.requested_plan_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'No se encontró el plan solicitado.';
    END IF;

    IF NOT v_plan.is_active THEN
      RAISE EXCEPTION 'No se puede aprobar un pago de un plan inactivo.';
    END IF;

    IF v_payment.currency <> 'USD'
       OR v_payment.amount <> v_plan.monthly_price THEN
      RAISE EXCEPTION 'El importe o la moneda del pago no coincide con el precio del plan.';
    END IF;

    -- Renovar una suscripción activa del mismo plan si existe.
    SELECT id, ends_at
      INTO v_subscription_id, v_old_end
      FROM public.business_subscriptions
     WHERE business_id = v_payment.business_id
       AND plan_id = v_payment.requested_plan_id
       AND status = 'active'
     ORDER BY ends_at DESC NULLS LAST, created_at DESC
     LIMIT 1
     FOR UPDATE;

    IF v_subscription_id IS NOT NULL THEN
      UPDATE public.business_subscriptions
         SET ends_at = GREATEST(COALESCE(v_old_end, now()), now()) + interval '1 month',
             device_limit = v_plan.included_devices,
             confirmed_payment_id = p_payment_id,
             updated_at = now()
       WHERE id = v_subscription_id;
    ELSE
      -- Cerrar suscripciones activas anteriores para evitar dos planes activos.
      UPDATE public.business_subscriptions
         SET status = 'expired',
             updated_at = now()
       WHERE business_id = v_payment.business_id
         AND status = 'active';

      INSERT INTO public.business_subscriptions (
        business_id, plan_id, status, started_at, ends_at,
        device_limit, confirmed_payment_id
      )
      VALUES (
        v_payment.business_id, v_payment.requested_plan_id, 'active',
        now(), now() + interval '1 month',
        v_plan.included_devices, p_payment_id
      )
      RETURNING id INTO v_subscription_id;
    END IF;

    UPDATE public.businesses
       SET status = 'active',
           updated_at = now()
     WHERE id = v_payment.business_id;

    UPDATE public.membership_payments
       SET payment_status = 'verified',
           subscription_id = v_subscription_id,
           bank_paid_at = COALESCE(p_bank_paid_at, bank_paid_at),
           verified_at = now(),
           verified_by = auth.uid(),
           verification_source = 'platform_admin'
     WHERE id = p_payment_id;
  ELSE
    UPDATE public.membership_payments
       SET payment_status = p_decision,
           verified_at = now(),
           verified_by = auth.uid(),
           verification_source = 'platform_admin'
     WHERE id = p_payment_id;
  END IF;

  INSERT INTO public.platform_audit_log (
    actor_user_id, business_id, action, entity_type, entity_id, details
  )
  VALUES (
    auth.uid(),
    v_payment.business_id,
    'membership_payment_' || p_decision,
    'membership_payment',
    p_payment_id::text,
    jsonb_build_object(
      'previous_status', v_payment.payment_status,
      'new_status', p_decision,
      'amount', v_payment.amount,
      'currency', v_payment.currency,
      'requested_plan_id', v_payment.requested_plan_id,
      'subscription_id', v_subscription_id
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION
  public.platform_admin_review_membership_payment(uuid, text, timestamptz)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.platform_admin_review_membership_payment(uuid, text, timestamptz)
  TO authenticated;
