-- ============================================================
-- 和平精英护航H5系统 - 数据库全量完整版 SQL
-- ============================================================

-- ============================================================
-- 一、通用函数
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = (SELECT auth.uid())
      AND role = 'admin'
  );
$$;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE ALL ON TABLES FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE ALL ON TABLES FROM authenticated;

-- ============================================================
-- 二、建表
-- ============================================================

-- 2.1 profiles 用户表（老板、打手、管理员统一）
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username text UNIQUE,
  nickname text,
  avatar text,
  phone text,
  qq text,
  role text NOT NULL DEFAULT 'client' CHECK (role IN ('client', 'booster', 'admin')),
  balance numeric(12,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
  frozen_balance numeric(12,2) NOT NULL DEFAULT 0 CHECK (frozen_balance >= 0),
  total_income numeric(12,2) NOT NULL DEFAULT 0,
  total_withdraw numeric(12,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'normal' CHECK (status IN ('normal', 'banned')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.profiles IS '用户资料表（老板、打手、管理员统一）';
COMMENT ON COLUMN public.profiles.id IS '用户ID，关联 auth.users';
COMMENT ON COLUMN public.profiles.username IS '登录用户名';
COMMENT ON COLUMN public.profiles.nickname IS '显示昵称';
COMMENT ON COLUMN public.profiles.avatar IS '头像URL';
COMMENT ON COLUMN public.profiles.phone IS '手机号';
COMMENT ON COLUMN public.profiles.qq IS 'QQ号';
COMMENT ON COLUMN public.profiles.role IS '角色：client=老板 booster=打手 admin=管理员';
COMMENT ON COLUMN public.profiles.balance IS '可用余额';
COMMENT ON COLUMN public.profiles.frozen_balance IS '冻结余额（下单后未结算金额）';
COMMENT ON COLUMN public.profiles.total_income IS '累计收入（打手用）';
COMMENT ON COLUMN public.profiles.total_withdraw IS '累计提现';
COMMENT ON COLUMN public.profiles.status IS '账号状态：normal=正常 banned=封禁';

-- 2.2 wallet_logs 钱包流水表
CREATE TABLE IF NOT EXISTS public.wallet_logs (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN ('recharge', 'pay', 'refund', 'income', 'withdraw', 'freeze', 'unfreeze', 'settle')),
  amount numeric(12,2) NOT NULL,
  balance_before numeric(12,2) NOT NULL,
  balance_after numeric(12,2) NOT NULL,
  frozen_before numeric(12,2) NOT NULL DEFAULT 0,
  frozen_after numeric(12,2) NOT NULL DEFAULT 0,
  order_id bigint,
  description text,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.wallet_logs IS '钱包流水表';
COMMENT ON COLUMN public.wallet_logs.id IS '流水ID';
COMMENT ON COLUMN public.wallet_logs.user_id IS '用户ID';
COMMENT ON COLUMN public.wallet_logs.type IS '流水类型';
COMMENT ON COLUMN public.wallet_logs.amount IS '变动金额';
COMMENT ON COLUMN public.wallet_logs.balance_before IS '变动前可用余额';
COMMENT ON COLUMN public.wallet_logs.balance_after IS '变动后可用余额';
COMMENT ON COLUMN public.wallet_logs.frozen_before IS '变动前冻结余额';
COMMENT ON COLUMN public.wallet_logs.frozen_after IS '变动后冻结余额';
COMMENT ON COLUMN public.wallet_logs.order_id IS '关联订单ID';
COMMENT ON COLUMN public.wallet_logs.description IS '备注说明';

-- 2.3 cards 充值卡密表
CREATE TABLE IF NOT EXISTS public.cards (
  id bigserial PRIMARY KEY,
  code text UNIQUE NOT NULL,
  amount numeric(12,2) NOT NULL CHECK (amount > 0),
  status text NOT NULL DEFAULT 'unused' CHECK (status IN ('unused', 'used')),
  used_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.cards IS '充值卡密表';
COMMENT ON COLUMN public.cards.id IS '卡密ID';
COMMENT ON COLUMN public.cards.code IS '卡密编码（唯一）';
COMMENT ON COLUMN public.cards.amount IS '卡密面值';
COMMENT ON COLUMN public.cards.status IS '状态：unused=未使用 used=已使用';
COMMENT ON COLUMN public.cards.used_by IS '使用者ID';
COMMENT ON COLUMN public.cards.used_at IS '使用时间';

-- 2.4 packages 套餐表
CREATE TABLE IF NOT EXISTS public.packages (
  id bigserial PRIMARY KEY,
  name text NOT NULL,
  description text,
  map_name text,
  rounds int,
  guarantee text,
  price numeric(12,2) NOT NULL CHECK (price > 0),
  allow_assign boolean NOT NULL DEFAULT false,
  assign_extra_price numeric(12,2) NOT NULL DEFAULT 0 CHECK (assign_extra_price >= 0),
  booster_share numeric(12,2) NOT NULL DEFAULT 0 CHECK (booster_share >= 0),
  sort_order int NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'on' CHECK (status IN ('on', 'off')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.packages IS '护航套餐表';
COMMENT ON COLUMN public.packages.id IS '套餐ID';
COMMENT ON COLUMN public.packages.name IS '套餐名称';
COMMENT ON COLUMN public.packages.description IS '套餐描述';
COMMENT ON COLUMN public.packages.map_name IS '地图名称';
COMMENT ON COLUMN public.packages.rounds IS '局数';
COMMENT ON COLUMN public.packages.guarantee IS '保证说明';
COMMENT ON COLUMN public.packages.price IS '售价';
COMMENT ON COLUMN public.packages.allow_assign IS '是否允许指定打手';
COMMENT ON COLUMN public.packages.assign_extra_price IS '指定打手加价';
COMMENT ON COLUMN public.packages.booster_share IS '打手分成金额';
COMMENT ON COLUMN public.packages.sort_order IS '排序序号';
COMMENT ON COLUMN public.packages.status IS '状态：on=启用 off=禁用';

-- 2.5 orders 订单表
CREATE TABLE IF NOT EXISTS public.orders (
  id bigserial PRIMARY KEY,
  order_no text UNIQUE NOT NULL,
  client_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE SET NULL,
  booster_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  package_id bigint NOT NULL REFERENCES public.packages(id),
  package_name text NOT NULL,
  amount numeric(12,2) NOT NULL CHECK (amount >= 0),
  booster_share numeric(12,2) NOT NULL DEFAULT 0 CHECK (booster_share >= 0),
  game_id text,
  remark text,
  status text NOT NULL DEFAULT 'pending_accept'
    CHECK (status IN (
      'pending_accept',
      'accepted',
      'in_progress',
      'completed_by_booster',
      'confirmed',
      'settled',
      'cancelled'
    )),
  version int NOT NULL DEFAULT 0,
  accepted_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  confirmed_at timestamptz,
  settled_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.orders IS '护航订单表';
COMMENT ON COLUMN public.orders.id IS '订单ID';
COMMENT ON COLUMN public.orders.order_no IS '订单号（唯一）';
COMMENT ON COLUMN public.orders.client_id IS '下单老板ID';
COMMENT ON COLUMN public.orders.booster_id IS '接单打手ID';
COMMENT ON COLUMN public.orders.package_id IS '套餐ID';
COMMENT ON COLUMN public.orders.package_name IS '套餐名称快照';
COMMENT ON COLUMN public.orders.amount IS '订单金额';
COMMENT ON COLUMN public.orders.booster_share IS '打手分成';
COMMENT ON COLUMN public.orders.game_id IS '老板游戏ID';
COMMENT ON COLUMN public.orders.remark IS '备注';
COMMENT ON COLUMN public.orders.status IS '订单状态：pending_accept=待接单 accepted=已接单 in_progress=服务中 completed_by_booster=打手提交完成 confirmed=老板确认 settled=已结算 cancelled=已取消';
COMMENT ON COLUMN public.orders.version IS '乐观锁版本号';

-- 2.6 order_logs 订单操作日志表
CREATE TABLE IF NOT EXISTS public.order_logs (
  id bigserial PRIMARY KEY,
  order_id bigint NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  operator_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  operator_role text NOT NULL CHECK (operator_role IN ('client', 'booster', 'admin', 'system')),
  action text NOT NULL,
  detail text,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.order_logs IS '订单操作日志表';
COMMENT ON COLUMN public.order_logs.id IS '日志ID';
COMMENT ON COLUMN public.order_logs.order_id IS '订单ID';
COMMENT ON COLUMN public.order_logs.operator_id IS '操作人ID';
COMMENT ON COLUMN public.order_logs.operator_role IS '操作人角色';
COMMENT ON COLUMN public.order_logs.action IS '操作动作';
COMMENT ON COLUMN public.order_logs.detail IS '操作详情';

-- 2.7 boosters 打手资质表
CREATE TABLE IF NOT EXISTS public.boosters (
  id bigserial PRIMARY KEY,
  user_id uuid UNIQUE NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  real_name text,
  id_card text,
  game_id text,
  game_rank text,
  experience text,
  certificate text,
  deposit numeric(12,2) NOT NULL DEFAULT 0 CHECK (deposit >= 0),
  rating numeric(2,1) NOT NULL DEFAULT 5.0 CHECK (rating >= 0 AND rating <= 5),
  order_count int NOT NULL DEFAULT 0,
  online_status text NOT NULL DEFAULT 'online' CHECK (online_status IN ('online', 'offline', 'busy')),
  accept_switch boolean NOT NULL DEFAULT true,
  audit_status text NOT NULL DEFAULT 'pending'
    CHECK (audit_status IN ('pending', 'approved', 'rejected')),
  approved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.boosters IS '打手资质认证表';
COMMENT ON COLUMN public.boosters.id IS '认证ID';
COMMENT ON COLUMN public.boosters.user_id IS '用户ID';
COMMENT ON COLUMN public.boosters.real_name IS '真实姓名';
COMMENT ON COLUMN public.boosters.id_card IS '身份证号';
COMMENT ON COLUMN public.boosters.game_id IS '游戏ID';
COMMENT ON COLUMN public.boosters.game_rank IS '游戏段位';
COMMENT ON COLUMN public.boosters.experience IS '护航经验描述';
COMMENT ON COLUMN public.boosters.certificate IS '资质证明图片URL';
COMMENT ON COLUMN public.boosters.deposit IS '保证金';
COMMENT ON COLUMN public.boosters.rating IS '服务评分';
COMMENT ON COLUMN public.boosters.order_count IS '完成订单数';
COMMENT ON COLUMN public.boosters.online_status IS '在线状态：online=在线 offline=离线 busy=忙';
COMMENT ON COLUMN public.boosters.accept_switch IS '接单开关';
COMMENT ON COLUMN public.boosters.audit_status IS '审核状态：pending=审核中 approved=已通过 rejected=已拒绝';

-- 2.8 withdrawals 提现申请表
CREATE TABLE IF NOT EXISTS public.withdrawals (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE SET NULL,
  amount numeric(12,2) NOT NULL CHECK (amount > 0),
  fee numeric(12,2) NOT NULL DEFAULT 0,
  actual_amount numeric(12,2) NOT NULL,
  pay_method text NOT NULL CHECK (pay_method IN ('alipay', 'wechat', 'bank')),
  pay_account text NOT NULL,
  pay_name text NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'paid')),
  admin_remark text,
  reviewed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.withdrawals IS '提现申请表';
COMMENT ON COLUMN public.withdrawals.id IS '提现ID';
COMMENT ON COLUMN public.withdrawals.user_id IS '申请人ID';
COMMENT ON COLUMN public.withdrawals.amount IS '申请金额';
COMMENT ON COLUMN public.withdrawals.fee IS '手续费';
COMMENT ON COLUMN public.withdrawals.actual_amount IS '实际到账金额';
COMMENT ON COLUMN public.withdrawals.pay_method IS '支付方式';
COMMENT ON COLUMN public.withdrawals.pay_account IS '收款账号';
COMMENT ON COLUMN public.withdrawals.pay_name IS '收款人姓名';
COMMENT ON COLUMN public.withdrawals.status IS '状态：pending=待审核 approved=已通过 rejected=已拒绝 paid=已打款';
COMMENT ON COLUMN public.withdrawals.admin_remark IS '管理员备注';
COMMENT ON COLUMN public.withdrawals.reviewed_by IS '审核人ID';
COMMENT ON COLUMN public.withdrawals.reviewed_at IS '审核时间';

-- ============================================================
-- 三、索引
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_profiles_status ON public.profiles(status);

CREATE INDEX IF NOT EXISTS idx_wallet_logs_user_id ON public.wallet_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_logs_type ON public.wallet_logs(type);
CREATE INDEX IF NOT EXISTS idx_wallet_logs_created_at ON public.wallet_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_logs_order_id ON public.wallet_logs(order_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_cards_code ON public.cards(code);
CREATE INDEX IF NOT EXISTS idx_cards_status ON public.cards(status);

CREATE INDEX IF NOT EXISTS idx_packages_status ON public.packages(status);
CREATE INDEX IF NOT EXISTS idx_packages_sort_order ON public.packages(sort_order);

CREATE INDEX IF NOT EXISTS idx_orders_client_id ON public.orders(client_id);
CREATE INDEX IF NOT EXISTS idx_orders_booster_id ON public.orders(booster_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_order_no ON public.orders(order_no);
CREATE INDEX IF NOT EXISTS idx_orders_pending_accept ON public.orders(status) WHERE status = 'pending_accept';

CREATE INDEX IF NOT EXISTS idx_order_logs_order_id ON public.order_logs(order_id);
CREATE INDEX IF NOT EXISTS idx_order_logs_created_at ON public.order_logs(created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_boosters_user_id ON public.boosters(user_id);
CREATE INDEX IF NOT EXISTS idx_boosters_audit_status ON public.boosters(audit_status);
CREATE INDEX IF NOT EXISTS idx_boosters_rating ON public.boosters(rating DESC);
CREATE INDEX IF NOT EXISTS idx_boosters_online_status ON public.boosters(online_status);
CREATE INDEX IF NOT EXISTS idx_boosters_accept_switch ON public.boosters(accept_switch) WHERE accept_switch = true;

CREATE INDEX IF NOT EXISTS idx_withdrawals_user_id ON public.withdrawals(user_id);
CREATE INDEX IF NOT EXISTS idx_withdrawals_status ON public.withdrawals(status);
CREATE INDEX IF NOT EXISTS idx_withdrawals_created_at ON public.withdrawals(created_at DESC);

-- ============================================================
-- 四、触发器
-- ============================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_profiles_updated_at ON public.profiles;
CREATE TRIGGER trigger_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trigger_packages_updated_at ON public.packages;
CREATE TRIGGER trigger_packages_updated_at
  BEFORE UPDATE ON public.packages
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trigger_orders_updated_at ON public.orders;
CREATE TRIGGER trigger_orders_updated_at
  BEFORE UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trigger_boosters_updated_at ON public.boosters;
CREATE TRIGGER trigger_boosters_updated_at
  BEFORE UPDATE ON public.boosters
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trigger_withdrawals_updated_at ON public.withdrawals;
CREATE TRIGGER trigger_withdrawals_updated_at
  BEFORE UPDATE ON public.withdrawals
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.increment_order_version()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.version := OLD.version + 1;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_orders_version ON public.orders;
CREATE TRIGGER trigger_orders_version
  BEFORE UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.increment_order_version();

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.profiles (id, role, status)
  VALUES (NEW.id, 'client', 'normal')
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_auth_new_user ON auth.users;
CREATE TRIGGER trigger_auth_new_user
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- 五、权限控制（防篡改）
-- ============================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.boosters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.withdrawals ENABLE ROW LEVEL SECURITY;

REVOKE UPDATE (balance, frozen_balance, role, total_income, total_withdraw)
  ON public.profiles FROM authenticated;

REVOKE INSERT, UPDATE, DELETE ON public.orders FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.boosters FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.wallet_logs FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.cards FROM authenticated;

GRANT SELECT ON public.profiles TO authenticated;
GRANT UPDATE (username, nickname, avatar, phone, qq) ON public.profiles TO authenticated;
GRANT SELECT ON public.wallet_logs TO authenticated;
GRANT SELECT ON public.packages TO authenticated;
GRANT SELECT ON public.orders TO authenticated;
GRANT SELECT ON public.order_logs TO authenticated;
GRANT SELECT ON public.boosters TO authenticated;
GRANT SELECT, INSERT ON public.withdrawals TO authenticated;

-- ============================================================
-- 六、RLS 策略
-- ============================================================

-- 6.1 profiles
DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
CREATE POLICY "profiles_select_own" ON public.profiles
  FOR SELECT
  USING ((SELECT auth.uid()) = id OR public.is_admin());

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE
  USING ((SELECT auth.uid()) = id);

DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
CREATE POLICY "profiles_insert_own" ON public.profiles
  FOR INSERT
  WITH CHECK ((SELECT auth.uid()) = id);

-- 6.2 wallet_logs
DROP POLICY IF EXISTS "wallet_logs_select_own" ON public.wallet_logs;
CREATE POLICY "wallet_logs_select_own" ON public.wallet_logs
  FOR SELECT
  USING ((SELECT auth.uid()) = user_id OR public.is_admin());

-- 6.3 cards（仅管理员）
DROP POLICY IF EXISTS "cards_select_admin" ON public.cards;
CREATE POLICY "cards_select_admin" ON public.cards
  FOR SELECT
  USING (public.is_admin());

DROP POLICY IF EXISTS "cards_insert_admin" ON public.cards;
CREATE POLICY "cards_insert_admin" ON public.cards
  FOR INSERT
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "cards_update_admin" ON public.cards;
CREATE POLICY "cards_update_admin" ON public.cards
  FOR UPDATE
  USING (public.is_admin());

-- 6.4 packages（公开读，管理员写）
DROP POLICY IF EXISTS "packages_select_all" ON public.packages;
CREATE POLICY "packages_select_all" ON public.packages
  FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "packages_write_admin" ON public.packages;
CREATE POLICY "packages_write_admin" ON public.packages
  FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- 6.5 orders（彻底禁止前端写，只能读自己相关的）
DROP POLICY IF EXISTS "orders_select_own" ON public.orders;
CREATE POLICY "orders_select_own" ON public.orders
  FOR SELECT
  USING (
    (SELECT auth.uid()) = client_id
    OR (SELECT auth.uid()) = booster_id
    OR public.is_admin()
  );

DROP POLICY IF EXISTS "orders_insert_disabled" ON public.orders;
CREATE POLICY "orders_insert_disabled" ON public.orders
  FOR INSERT
  WITH CHECK (false);

DROP POLICY IF EXISTS "orders_update_disabled" ON public.orders;
CREATE POLICY "orders_update_disabled" ON public.orders
  FOR UPDATE
  USING (false)
  WITH CHECK (false);

-- 6.6 order_logs
DROP POLICY IF EXISTS "order_logs_select_own" ON public.order_logs;
CREATE POLICY "order_logs_select_own" ON public.order_logs
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_logs.order_id
        AND (o.client_id = (SELECT auth.uid()) OR o.booster_id = (SELECT auth.uid()))
    )
    OR public.is_admin()
  );

-- 6.7 boosters（彻底禁止前端写，只能读）
DROP POLICY IF EXISTS "boosters_select_all" ON public.boosters;
CREATE POLICY "boosters_select_all" ON public.boosters
  FOR SELECT
  USING (audit_status = 'approved' OR (SELECT auth.uid()) = user_id OR public.is_admin());

DROP POLICY IF EXISTS "boosters_insert_disabled" ON public.boosters;
CREATE POLICY "boosters_insert_disabled" ON public.boosters
  FOR INSERT
  WITH CHECK (false);

DROP POLICY IF EXISTS "boosters_update_disabled" ON public.boosters;
CREATE POLICY "boosters_update_disabled" ON public.boosters
  FOR UPDATE
  USING (false)
  WITH CHECK (false);

-- 6.8 withdrawals
DROP POLICY IF EXISTS "withdrawals_select_own" ON public.withdrawals;
CREATE POLICY "withdrawals_select_own" ON public.withdrawals
  FOR SELECT
  USING ((SELECT auth.uid()) = user_id OR public.is_admin());

DROP POLICY IF EXISTS "withdrawals_insert_own" ON public.withdrawals;
CREATE POLICY "withdrawals_insert_own" ON public.withdrawals
  FOR INSERT
  WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "withdrawals_update_admin" ON public.withdrawals;
CREATE POLICY "withdrawals_update_admin" ON public.withdrawals
  FOR UPDATE
  USING (public.is_admin());

-- ============================================================
-- 七、RPC 函数
-- ============================================================

-- 7.1 rpc_recharge_balance - 卡密充值
CREATE OR REPLACE FUNCTION public.rpc_recharge_balance(card_code text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_card public.cards%ROWTYPE;
  v_user_id uuid;
  v_old_balance numeric(12,2);
  v_new_balance numeric(12,2);
  v_log_id bigint;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION '未登录';
  END IF;

  SELECT * INTO v_card
  FROM public.cards
  WHERE code = card_code
  FOR UPDATE;

  IF v_card.id IS NULL THEN
    RAISE EXCEPTION '卡密不存在';
  END IF;

  IF v_card.status = 'used' THEN
    RAISE EXCEPTION '卡密已使用';
  END IF;

  SELECT balance INTO v_old_balance
  FROM public.profiles
  WHERE id = v_user_id;

  v_new_balance := v_old_balance + v_card.amount;

  UPDATE public.profiles
  SET balance = v_new_balance
  WHERE id = v_user_id;

  UPDATE public.cards
  SET status = 'used',
      used_by = v_user_id,
      used_at = now()
  WHERE id = v_card.id;

  INSERT INTO public.wallet_logs (
    user_id, type, amount, balance_before, balance_after, description
  ) VALUES (
    v_user_id, 'recharge', v_card.amount, v_old_balance, v_new_balance,
    '卡密充值：' || card_code
  ) RETURNING id INTO v_log_id;

  RETURN json_build_object(
    'success', true,
    'amount', v_card.amount,
    'balance', v_new_balance,
    'log_id', v_log_id
  );
END;
$$;

-- 7.2 rpc_create_order - 创建订单（余额冻结机制）
CREATE OR REPLACE FUNCTION public.rpc_create_order(
  p_package_id bigint,
  p_game_id text,
  p_remark text,
  p_booster_id uuid DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_client_id uuid;
  v_package public.packages%ROWTYPE;
  v_client public.profiles%ROWTYPE;
  v_order_no text;
  v_order_id bigint;
  v_booster_cert public.boosters%ROWTYPE;
  v_total_amount numeric(12,2);
  v_new_balance numeric(12,2);
  v_new_frozen numeric(12,2);
BEGIN
  v_client_id := auth.uid();
  IF v_client_id IS NULL THEN
    RAISE EXCEPTION '未登录';
  END IF;

  SELECT * INTO v_client
  FROM public.profiles
  WHERE id = v_client_id
  FOR UPDATE;

  IF v_client.status = 'banned' THEN
    RAISE EXCEPTION '账号已封禁';
  END IF;

  SELECT * INTO v_package
  FROM public.packages
  WHERE id = p_package_id AND status = 'on';

  IF v_package.id IS NULL THEN
    RAISE EXCEPTION '套餐不存在或已下架';
  END IF;

  -- 指定打手时校验
  IF p_booster_id IS NOT NULL THEN
    IF v_package.allow_assign != true THEN
      RAISE EXCEPTION '该套餐不支持指定打手';
    END IF;

    SELECT * INTO v_booster_cert
    FROM public.boosters
    WHERE user_id = p_booster_id;

    IF v_booster_cert.id IS NULL THEN
      RAISE EXCEPTION '该打手不存在';
    END IF;

    IF v_booster_cert.audit_status != 'approved' THEN
      RAISE EXCEPTION '该打手未通过认证';
    END IF;

    v_total_amount := v_package.price + v_package.assign_extra_price;
  ELSE
    v_total_amount := v_package.price;
  END IF;

  IF v_client.balance < v_total_amount THEN
    RAISE EXCEPTION '余额不足';
  END IF;

  v_order_no := 'HP' || to_char(now(), 'YYYYMMDDHH24MISS') || lpad(floor(random() * 10000)::text, 4, '0');

  -- 余额冻结：balance -= amount, frozen_balance += amount
  v_new_balance := v_client.balance - v_total_amount;
  v_new_frozen := v_client.frozen_balance + v_total_amount;

  UPDATE public.profiles
  SET balance = v_new_balance,
      frozen_balance = v_new_frozen
  WHERE id = v_client_id;

  INSERT INTO public.wallet_logs (
    user_id, type, amount, balance_before, balance_after,
    frozen_before, frozen_after, description
  ) VALUES (
    v_client_id, 'freeze', -v_total_amount,
    v_client.balance, v_new_balance,
    v_client.frozen_balance, v_new_frozen,
    '下单冻结：' || v_package.name
  );

  INSERT INTO public.orders (
    order_no, client_id, booster_id, package_id,
    package_name, amount, booster_share,
    game_id, remark, status
  ) VALUES (
    v_order_no, v_client_id, p_booster_id, v_package.id,
    v_package.name, v_total_amount, v_package.booster_share,
    p_game_id, p_remark,
    CASE WHEN p_booster_id IS NOT NULL THEN 'accepted' ELSE 'pending_accept' END
  ) RETURNING id INTO v_order_id;

  IF p_booster_id IS NOT NULL THEN
    UPDATE public.orders
    SET accepted_at = now()
    WHERE id = v_order_id;

    INSERT INTO public.order_logs (order_id, operator_id, operator_role, action, detail)
    VALUES (v_order_id, v_client_id, 'client', '指定打手下单', '指定打手ID：' || p_booster_id::text);
  ELSE
    INSERT INTO public.order_logs (order_id, operator_id, operator_role, action, detail)
    VALUES (v_order_id, v_client_id, 'client', '创建订单', '老板下单，等待打手接单');
  END IF;

  RETURN json_build_object(
    'success', true,
    'order_id', v_order_id,
    'order_no', v_order_no,
    'amount', v_total_amount,
    'status', CASE WHEN p_booster_id IS NOT NULL THEN 'accepted' ELSE 'pending_accept' END,
    'balance', v_new_balance,
    'frozen_balance', v_new_frozen
  );
END;
$$;

-- 7.3 rpc_grab_order - 打手抢单（乐观锁防超抢 + 接单开关校验）
CREATE OR REPLACE FUNCTION public.rpc_grab_order(
  p_order_id bigint,
  p_expected_version int
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_booster_id uuid;
  v_booster_profile public.profiles%ROWTYPE;
  v_booster_cert public.boosters%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_row_count int;
BEGIN
  v_booster_id := auth.uid();
  IF v_booster_id IS NULL THEN
    RAISE EXCEPTION '未登录';
  END IF;

  SELECT * INTO v_booster_profile
  FROM public.profiles
  WHERE id = v_booster_id;

  IF v_booster_profile.role != 'booster' THEN
    RAISE EXCEPTION '您不是打手身份';
  END IF;

  IF v_booster_profile.status = 'banned' THEN
    RAISE EXCEPTION '账号已封禁';
  END IF;

  SELECT * INTO v_booster_cert
  FROM public.boosters
  WHERE user_id = v_booster_id;

  IF v_booster_cert.id IS NULL OR v_booster_cert.audit_status != 'approved' THEN
    RAISE EXCEPTION '您的打手资质未通过审核';
  END IF;

  IF v_booster_cert.accept_switch != true THEN
    RAISE EXCEPTION '您已关闭接单开关，请先开启';
  END IF;

  IF v_booster_cert.online_status = 'offline' THEN
    RAISE EXCEPTION '您当前处于离线状态，无法接单';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION '订单不存在';
  END IF;

  IF v_order.client_id = v_booster_id THEN
    RAISE EXCEPTION '不能抢自己下的订单';
  END IF;

  -- 乐观锁抢单：版本号 + 状态双重校验
  UPDATE public.orders
  SET booster_id = v_booster_id,
      status = 'accepted',
      accepted_at = now()
  WHERE id = p_order_id
    AND version = p_expected_version
    AND status = 'pending_accept';

  GET DIAGNOSTICS v_row_count = ROW_COUNT;

  IF v_row_count = 0 THEN
    RAISE EXCEPTION '手慢了，订单已被抢走或状态已变更';
  END IF;

  INSERT INTO public.order_logs (order_id, operator_id, operator_role, action, detail)
  VALUES (p_order_id, v_booster_id, 'booster', '抢单成功', '打手接单');

  RETURN json_build_object(
    'success', true,
    'order_id', p_order_id,
    'status', 'accepted',
    'accepted_at', now()
  );
END;
$$;

-- 7.4 rpc_start_order - 打手开始服务
CREATE OR REPLACE FUNCTION public.rpc_start_order(p_order_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_booster_id uuid;
  v_order public.orders%ROWTYPE;
BEGIN
  v_booster_id := auth.uid();
  IF v_booster_id IS NULL THEN
    RAISE EXCEPTION '未登录';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION '订单不存在';
  END IF;

  IF v_order.booster_id != v_booster_id THEN
    RAISE EXCEPTION '您不是该订单的打手';
  END IF;

  IF v_order.status != 'accepted' THEN
    RAISE EXCEPTION '订单状态不正确，无法开始服务';
  END IF;

  UPDATE public.orders
  SET status = 'in_progress',
      started_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_logs (order_id, operator_id, operator_role, action, detail)
  VALUES (p_order_id, v_booster_id, 'booster', '开始服务', '打手开始护航服务');

  RETURN json_build_object(
    'success', true,
    'order_id', p_order_id,
    'status', 'in_progress',
    'started_at', now()
  );
END;
$$;

-- 7.5 rpc_complete_by_booster - 打手提交完成
CREATE OR REPLACE FUNCTION public.rpc_complete_by_booster(p_order_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_booster_id uuid;
  v_order public.orders%ROWTYPE;
BEGIN
  v_booster_id := auth.uid();
  IF v_booster_id IS NULL THEN
    RAISE EXCEPTION '未登录';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION '订单不存在';
  END IF;

  IF v_order.booster_id != v_booster_id THEN
    RAISE EXCEPTION '您不是该订单的打手';
  END IF;

  IF v_order.status != 'in_progress' THEN
    RAISE EXCEPTION '订单状态不正确，无法提交完成';
  END IF;

  UPDATE public.orders
  SET status = 'completed_by_booster',
      completed_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_logs (order_id, operator_id, operator_role, action, detail)
  VALUES (p_order_id, v_booster_id, 'booster', '提交完成', '打手提交服务完成，等待老板确认');

  RETURN json_build_object(
    'success', true,
    'order_id', p_order_id,
    'status', 'completed_by_booster',
    'completed_at', now()
  );
END;
$$;

-- 7.6 rpc_confirm_order - 老板确认完成并结算
CREATE OR REPLACE FUNCTION public.rpc_confirm_order(p_order_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_client_id uuid;
  v_order public.orders%ROWTYPE;
  v_client_old_balance numeric(12,2);
  v_client_old_frozen numeric(12,2);
  v_client_new_frozen numeric(12,2);
  v_booster_old_balance numeric(12,2);
  v_booster_new_balance numeric(12,2);
BEGIN
  v_client_id := auth.uid();
  IF v_client_id IS NULL THEN
    RAISE EXCEPTION '未登录';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION '订单不存在';
  END IF;

  IF v_order.client_id != v_client_id THEN
    RAISE EXCEPTION '您不是该订单的老板';
  END IF;

  IF v_order.status != 'completed_by_booster' THEN
    RAISE EXCEPTION '订单状态不正确，无法确认';
  END IF;

  IF v_order.booster_id IS NULL THEN
    RAISE EXCEPTION '订单没有打手，无法结算';
  END IF;

  UPDATE public.orders
  SET status = 'settled',
      confirmed_at = now(),
      settled_at = now()
  WHERE id = p_order_id;

  -- 老板侧：解冻扣除
  SELECT balance, frozen_balance INTO v_client_old_balance, v_client_old_frozen
  FROM public.profiles
  WHERE id = v_client_id;

  v_client_new_frozen := v_client_old_frozen - v_order.amount;

  UPDATE public.profiles
  SET frozen_balance = v_client_new_frozen
  WHERE id = v_client_id;

  INSERT INTO public.wallet_logs (
    user_id, type, amount, balance_before, balance_after,
    frozen_before, frozen_after, order_id, description
  ) VALUES (
    v_client_id, 'settle', -v_order.amount,
    v_client_old_balance, v_client_old_balance,
    v_client_old_frozen, v_client_new_frozen,
    p_order_id, '订单结算解冻：' || v_order.package_name
  );

  -- 打手侧：分成入账
  SELECT balance INTO v_booster_old_balance
  FROM public.profiles
  WHERE id = v_order.booster_id;

  v_booster_new_balance := v_booster_old_balance + v_order.booster_share;

  UPDATE public.profiles
  SET balance = v_booster_new_balance,
      total_income = total_income + v_order.booster_share
  WHERE id = v_order.booster_id;

  INSERT INTO public.wallet_logs (
    user_id, type, amount, balance_before, balance_after, order_id, description
  ) VALUES (
    v_order.booster_id, 'income', v_order.booster_share,
    v_booster_old_balance, v_booster_new_balance,
    p_order_id, '订单结算收入：' || v_order.package_name
  );

  UPDATE public.boosters
  SET order_count = order_count + 1
  WHERE user_id = v_order.booster_id;

  INSERT INTO public.order_logs (order_id, operator_id, operator_role, action, detail)
  VALUES (p_order_id, v_client_id, 'client', '确认完成', '老板确认服务完成，订单已结算');

  RETURN json_build_object(
    'success', true,
    'order_id', p_order_id,
    'status', 'settled',
    'settled_at', now(),
    'booster_earned', v_order.booster_share
  );
END;
$$;

-- 7.7 rpc_cancel_order - 取消订单（解冻退回）
CREATE OR REPLACE FUNCTION public.rpc_cancel_order(p_order_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_client_id uuid;
  v_order public.orders%ROWTYPE;
  v_client_old_balance numeric(12,2);
  v_client_old_frozen numeric(12,2);
  v_client_new_balance numeric(12,2);
  v_client_new_frozen numeric(12,2);
BEGIN
  v_client_id := auth.uid();
  IF v_client_id IS NULL THEN
    RAISE EXCEPTION '未登录';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION '订单不存在';
  END IF;

  IF v_order.client_id != v_client_id THEN
    RAISE EXCEPTION '您不是该订单的老板';
  END IF;

  IF v_order.status NOT IN ('pending_accept', 'accepted') THEN
    RAISE EXCEPTION '订单服务中或已完成，无法取消';
  END IF;

  UPDATE public.orders
  SET status = 'cancelled',
      cancelled_at = now()
  WHERE id = p_order_id;

  SELECT balance, frozen_balance INTO v_client_old_balance, v_client_old_frozen
  FROM public.profiles
  WHERE id = v_client_id
  FOR UPDATE;

  v_client_new_balance := v_client_old_balance + v_order.amount;
  v_client_new_frozen := v_client_old_frozen - v_order.amount;

  UPDATE public.profiles
  SET balance = v_client_new_balance,
      frozen_balance = v_client_new_frozen
  WHERE id = v_client_id;

  INSERT INTO public.wallet_logs (
    user_id, type, amount, balance_before, balance_after,
    frozen_before, frozen_after, order_id, description
  ) VALUES (
    v_client_id, 'unfreeze', v_order.amount,
    v_client_old_balance, v_client_new_balance,
    v_client_old_frozen, v_client_new_frozen,
    p_order_id, '订单取消解冻：' || v_order.package_name
  );

  INSERT INTO public.order_logs (order_id, operator_id, operator_role, action, detail)
  VALUES (p_order_id, v_client_id, 'client', '取消订单', '老板取消订单，已解冻退款');

  RETURN json_build_object(
    'success', true,
    'order_id', p_order_id,
    'status', 'cancelled',
    'refund_amount', v_order.amount,
    'balance', v_client_new_balance,
    'frozen_balance', v_client_new_frozen
  );
END;
$$;

-- 7.8 rpc_apply_withdraw - 申请提现
CREATE OR REPLACE FUNCTION public.rpc_apply_withdraw(
  p_amount numeric(12,2),
  p_pay_method text,
  p_pay_account text,
  p_pay_name text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_user public.profiles%ROWTYPE;
  v_fee_rate numeric(4,3);
  v_fee numeric(12,2);
  v_actual numeric(12,2);
  v_withdraw_id bigint;
  v_new_balance numeric(12,2);
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION '未登录';
  END IF;

  SELECT * INTO v_user
  FROM public.profiles
  WHERE id = v_user_id
  FOR UPDATE;

  IF v_user.balance < p_amount THEN
    RAISE EXCEPTION '余额不足';
  END IF;

  IF p_amount < 10 THEN
    RAISE EXCEPTION '最低提现金额为10元';
  END IF;

  v_fee_rate := 0.01;
  v_fee := round(p_amount * v_fee_rate, 2);
  v_actual := p_amount - v_fee;

  v_new_balance := v_user.balance - p_amount;
  UPDATE public.profiles
  SET balance = v_new_balance
  WHERE id = v_user_id;

  INSERT INTO public.wallet_logs (
    user_id, type, amount, balance_before, balance_after, description
  ) VALUES (
    v_user_id, 'withdraw', -p_amount, v_user.balance, v_new_balance,
    '申请提现，手续费：' || v_fee
  );

  INSERT INTO public.withdrawals (
    user_id, amount, fee, actual_amount, pay_method, pay_account, pay_name, status
  ) VALUES (
    v_user_id, p_amount, v_fee, v_actual, p_pay_method, p_pay_account, p_pay_name, 'pending'
  ) RETURNING id INTO v_withdraw_id;

  RETURN json_build_object(
    'success', true,
    'withdraw_id', v_withdraw_id,
    'amount', p_amount,
    'fee', v_fee,
    'actual_amount', v_actual,
    'status', 'pending'
  );
END;
$$;
