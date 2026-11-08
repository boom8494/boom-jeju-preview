(() => {
  'use strict';

  const panel = document.getElementById('boomPushAdmin');
  if (!panel || !window.supabase?.createClient) return;

  const API = 'https://rfpwbwivdlagqjkhjsxq.supabase.co';
  const PUBLISHABLE_KEY = 'sb_publishable_IAqXgHQU6Yh4DpxtkElBbg_Pl-oe5-Y';
  const client = window.supabase.createClient(API, PUBLISHABLE_KEY);
  const status = document.getElementById('boomPushStatus');
  const enable = document.getElementById('boomPushEnable');
  const list = document.getElementById('boomNotificationList');
  const countLabel = document.getElementById('boomNotificationCount');
  let currentUser = null;
  let channel = null;
  let refreshing = false;

  const say = (message) => { status.textContent = message; };

  function decodeVapidKey(value) {
    const padded = value + '='.repeat((4 - value.length % 4) % 4);
    const raw = atob(padded.replace(/-/g, '+').replace(/_/g, '/'));
    return Uint8Array.from(raw, (character) => character.charCodeAt(0));
  }

  async function updateBadge(count) {
    const safeCount = Math.max(0, Number(count) || 0);
    try {
      if ('setAppBadge' in navigator && safeCount) await navigator.setAppBadge(safeCount);
      else if ('clearAppBadge' in navigator) await navigator.clearAppBadge();
      const registration = await navigator.serviceWorker?.ready;
      registration?.active?.postMessage({ type: 'BOOM_SET_BADGE', count: safeCount });
    } catch (error) {
      console.debug('App badge is unavailable on this device.', error);
    }
  }

  async function markRead(id) {
    const { error } = await client.from('boom_notifications')
      .update({ read_at: new Date().toISOString() })
      .eq('id', id)
      .is('read_at', null);
    if (error) throw error;
  }

  async function refreshNotifications() {
    if (!currentUser || refreshing) return;
    refreshing = true;
    try {
      const { data, error } = await client.from('boom_notifications')
        .select('id,kind,title,body,link,read_at,created_at')
        .order('created_at', { ascending: false })
        .limit(30);
      if (error) throw error;

      const rows = data || [];
      const unread = rows.filter((row) => !row.read_at).length;
      countLabel.textContent = unread ? `읽지 않은 알림 ${unread}건` : '새 알림이 없습니다.';
      await updateBadge(unread);
      list.replaceChildren();

      if (!rows.length) {
        const empty = document.createElement('p');
        empty.className = 'hint';
        empty.textContent = '새 문의나 공개 게시물이 생기면 여기에 표시됩니다.';
        list.append(empty);
      }

      for (const row of rows) {
        const item = document.createElement('article');
        item.className = `boom-notification-item${row.read_at ? '' : ' is-unread'}`;
        const link = document.createElement('a');
        link.href = row.link || '/#staffLogin';
        link.textContent = row.title;
        link.addEventListener('click', async (event) => {
          event.preventDefault();
          try {
            if (!row.read_at) await markRead(row.id);
            const target = new URL(link.href, location.origin);
            if (target.origin === location.origin) location.href = target.href;
            else location.hash = '#staffLogin';
          } catch (error) {
            say(`읽음 처리에 실패했습니다: ${error.message}`);
          }
        });
        const text = document.createElement('p');
        text.textContent = row.body;
        const time = document.createElement('small');
        time.textContent = new Date(row.created_at).toLocaleString('ko-KR');
        item.append(link, text, time);
        list.append(item);
      }
      say('새 글·문의 알림을 이 기기에서 확인할 수 있습니다.');
    } catch (error) {
      countLabel.textContent = '알림 연결을 확인해 주세요.';
      say('Supabase 알림 SQL 설정이 적용된 뒤 사용할 수 있습니다.');
      console.error('BOOM notifications:', error);
    } finally {
      refreshing = false;
    }
  }

  async function updateSubscriptionButton() {
    if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) {
      enable.disabled = true;
      enable.textContent = '이 기기는 앱 푸시 알림을 지원하지 않습니다';
      return;
    }
    try {
      const registration = await navigator.serviceWorker.ready;
      const subscription = await registration.pushManager.getSubscription();
      enable.textContent = subscription ? '이 기기 알림 끄기' : '새 글·문의 알림 받기';
    } catch {
      enable.textContent = '새 글·문의 알림 받기';
    }
  }

  async function toggleSubscription() {
    if (!currentUser) return;
    enable.disabled = true;
    try {
      const registration = await navigator.serviceWorker.ready;
      const existing = await registration.pushManager.getSubscription();
      if (existing) {
        const endpoint = existing.endpoint;
        await existing.unsubscribe();
        const { error } = await client.from('boom_push_subscriptions').delete().eq('endpoint', endpoint);
        if (error) throw error;
        say('이 기기의 푸시 알림을 껐습니다.');
      } else {
        const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
          (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
        const standalone = window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone;
        if (isIOS && !standalone) {
          say('iPhone에서는 먼저 Safari의 공유 메뉴에서 홈 화면에 추가한 뒤 앱을 열어 주세요.');
          return;
        }

        const permission = await Notification.requestPermission();
        if (permission !== 'granted') {
          say('휴대폰 설정에서 BOOM JEJU 알림을 허용해 주세요.');
          return;
        }
        const { data: keyData, error: keyError } = await client.functions.invoke('boom-push', {
          body: { action: 'public_key' },
        });
        if (keyError || !keyData?.publicKey) throw keyError || new Error('VAPID 공개키가 설정되지 않았습니다.');
        const subscription = await registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: decodeVapidKey(keyData.publicKey),
        });
        const { error } = await client.from('boom_push_subscriptions').upsert({
          user_id: currentUser.id,
          endpoint: subscription.endpoint,
          subscription: subscription.toJSON(),
          updated_at: new Date().toISOString(),
        }, { onConflict: 'endpoint' });
        if (error) {
          await subscription.unsubscribe();
          throw error;
        }
        say('이 기기에서 새 문의와 공개 게시물 알림을 받습니다.');
      }
      await updateSubscriptionButton();
    } catch (error) {
      say(`알림 설정에 실패했습니다: ${error.message}`);
      console.error('BOOM push setup:', error);
    } finally {
      enable.disabled = false;
    }
  }

  async function configureUser(user) {
    if (channel) {
      await client.removeChannel(channel);
      channel = null;
    }
    currentUser = user || null;
    if (!currentUser) {
      panel.hidden = true;
      await updateBadge(0);
      return;
    }

    const { data, error } = await client.from('staff_profiles')
      .select('approved,is_superadmin')
      .eq('user_id', currentUser.id)
      .maybeSingle();
    if (error || data?.approved !== true || data?.is_superadmin !== true) {
      panel.hidden = true;
      await updateBadge(0);
      return;
    }

    panel.hidden = false;
    await updateSubscriptionButton();
    await refreshNotifications();
    channel = client.channel(`boom-notifications-${currentUser.id}`)
      .on('postgres_changes', {
        event: '*', schema: 'public', table: 'boom_notifications',
        filter: `user_id=eq.${currentUser.id}`,
      }, refreshNotifications)
      .subscribe();
  }

  enable.addEventListener('click', toggleSubscription);
  client.auth.onAuthStateChange((_event, session) => {
    setTimeout(() => configureUser(session?.user || null), 0);
  });
  client.auth.getUser().then(({ data }) => configureUser(data.user || null));

  const notificationId = new URL(location.href).searchParams.get('boom_notification');
  if (notificationId) {
    client.auth.getUser().then(async ({ data }) => {
      if (!data.user) return;
      try {
        await client.from('boom_notifications').update({ read_at: new Date().toISOString() })
          .eq('id', notificationId).is('read_at', null);
      } finally {
        const url = new URL(location.href);
        url.searchParams.delete('boom_notification');
        history.replaceState(null, '', url.pathname + url.search + url.hash);
        await configureUser(data.user);
      }
    });
  }

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') refreshNotifications();
  });
  window.addEventListener('focus', refreshNotifications);
  setInterval(() => {
    if (document.visibilityState === 'visible') refreshNotifications();
  }, 60000);
})();
