(function () {
  var carpetas = {
    windows: "descargas/windows/",
    windowsPortable: "descargas/windows/",
    android: "descargas/android/"
  };

  function mb(bytes) {
    var n = bytes / 1048576;
    return n.toLocaleString("es-PE", {
      minimumFractionDigits: 1,
      maximumFractionDigits: 1
    }) + " MB";
  }

  function nombreSeguro(nombre) {
    if (typeof nombre !== "string") return "";
    var limpio = nombre.trim();
    if (!limpio || /[\\/]/.test(limpio) || limpio.indexOf("..") !== -1) return "";
    return limpio;
  }

  function destino(item, clave) {
    if (!item || !carpetas[clave]) return null;
    if (typeof item.url === "string" && item.url.trim().indexOf("https://") === 0) {
      return { href: item.url.trim(), externo: true, nombre: nombreSeguro(item.archivo) };
    }
    var nombre = nombreSeguro(item.archivo);
    if (!nombre) return null;
    return { href: carpetas[clave] + nombre, externo: false, nombre: nombre };
  }

  function aplicar(clave, info) {
    var nodos = document.querySelectorAll('[data-enlace="' + clave + '"]');
    for (var i = 0; i < nodos.length; i++) {
      var a = nodos[i];
      if (!info) {
        a.setAttribute("aria-disabled", "true");
        a.classList.add("is-disabled");
        a.setAttribute("href", "#descargas");
        a.removeAttribute("download");
        continue;
      }
      a.setAttribute("href", info.href);
      a.classList.remove("is-disabled");
      a.removeAttribute("aria-disabled");
      if (info.externo) {
        a.removeAttribute("download");
        a.setAttribute("rel", "noopener");
      } else if (info.nombre) {
        a.setAttribute("download", info.nombre);
        a.removeAttribute("target");
      }
    }
    var rutas = document.querySelectorAll('[data-ruta="' + clave + '"]');
    for (var r = 0; r < rutas.length; r++) {
      rutas[r].textContent = info ? info.nombre || info.href : "sin archivo";
    }
    if (info && !info.externo) medir(clave, info.href);
  }

  function medir(clave, href) {
    fetch(href, { method: "HEAD" }).then(function (res) {
      if (!res.ok) return;
      var len = Number(res.headers.get("content-length"));
      if (!len) return;
      var texto = mb(len);
      var sitios = document.querySelectorAll('[data-tamano="' + clave + '"]');
      for (var i = 0; i < sitios.length; i++) sitios[i].textContent = texto + " · ";
    }).catch(function () {});
  }

  fetch("enlaces.json", { cache: "no-store" })
    .then(function (res) {
      if (!res.ok) throw new Error("enlaces");
      return res.json();
    })
    .then(function (data) {
      var version = typeof data.version === "string" && data.version.trim() ? data.version.trim() : "2.0.2";
      var marcas = document.querySelectorAll("[data-version]");
      for (var i = 0; i < marcas.length; i++) marcas[i].textContent = version;
      ["windows", "windowsPortable", "android"].forEach(function (clave) {
        aplicar(clave, destino(data[clave], clave));
      });
    })
    .catch(function () {});
})();
