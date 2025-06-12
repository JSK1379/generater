// 顯示今天日期
const dateElem = document.getElementById('date');
const today = new Date();
const y = today.getFullYear();
const m = today.getMonth() + 1;
const d = today.getDate();
dateElem.textContent = `${y}年${m}月${d}日`;

// 取得台北天氣與濕度（OpenWeatherMap API）
const weatherElem = document.getElementById('weather');
const humidityElem = document.getElementById('humidity');
const apiKey = '47981927ad46872c099eb22165d1a573'; // 請至 https://openweathermap.org/ 申請免費 API 金鑰
const url = `https://api.openweathermap.org/data/2.5/weather?q=Taipei,TW&appid=${apiKey}&units=metric&lang=zh_tw`;

fetch(url)
  .then(res => res.json())
  .then(data => {
    weatherElem.textContent = data.weather[0].description;
    humidityElem.textContent = data.main.humidity + '%';
  })
  .catch(() => {
    weatherElem.textContent = '無法取得';
    humidityElem.textContent = '無法取得';
  });

// 月相計算（簡易版）
function getMoonPhase(date) {
  // 參考演算法: https://www.subsystems.us/uploads/9/8/9/4/98948044/moonphase.pdf
  const year = date.getFullYear();
  const month = date.getMonth() + 1;
  const day = date.getDate();
  let c = 0, e = 0;
  let jd = 0;
  if (month < 3) {
    year--;
    month += 12;
  }
  ++month;
  c = 365.25 * year;
  e = 30.6 * month;
  jd = c + e + day - 694039.09; // jd is total days elapsed
  jd /= 29.5305882; // divide by the moon cycle
  const b = parseInt(jd); // int(jd) -> b, take integer part of jd
  jd -= b; // subtract integer part to leave fractional part of original jd
  const phase = Math.round(jd * 8);
  const phases = ['新月', '蛾眉月', '上弦月', '盈凸月', '滿月', '虧凸月', '下弦月', '殘月', '新月'];
  return phases[phase];
}

document.getElementById('moon').textContent = getMoonPhase(today);
