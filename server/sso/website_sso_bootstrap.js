(function () {
  var hash = location.hash || '';
  var match = hash.match(/(?:^#|&)sso_code=([^&]+)/);
  if (!match) return;
  var code = decodeURIComponent(match[1]);
  history.replaceState(null, '', location.pathname + location.search + '#account');
  fetch('https://auth.jiaofangsi.top/wechat-auth/v1/sso/redeem', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code: code })
  }).then(async function (res) {
    var body = null;
    try { body = await res.json(); } catch (e) {}
    if (!res.ok || !body || body.success === false) {
      throw new Error((body && (body.error && body.error.message || body.error || body.message)) || '登录码无效');
    }
    var user;
    if (body.mode === 'legacy') {
      user = {
        mode: 'legacy',
        user_id: body.user_id || '',
        token: body.token || body.access_token || '',
        login_name: body.login_name || body.display_name || '',
        display_name: body.display_name || body.login_name || '',
        avatar_url: body.avatar_url || '',
        avatar_type: body.avatar_type || 'male'
      };
    } else {
      var nickname = (body.user && body.user.nickname) || body.stage_name || body.account_id || '用户';
      user = {
        mode: 'unified',
        account_id: body.account_id || '',
        token: body.access_token || '',
        refresh_token: body.refresh_token || '',
        access_expires_at: body.access_expires_at || '',
        refresh_expires_at: body.refresh_expires_at || '',
        display_name: nickname,
        login_name: body.bound_email || nickname,
        email_login: body.bound_email || '',
        avatar_url: (body.user && body.user.avatar_url) || '',
        avatar_type: 'male'
      };
    }
    user.saved_at = Date.now();
    localStorage.setItem('jiaofangsi_user', JSON.stringify(user));
    location.replace('/personal-center#account');
  }).catch(function (err) {
    alert('个人中心登录失败：' + (err && err.message ? err.message : '请返回软件重试'));
  });
})();
