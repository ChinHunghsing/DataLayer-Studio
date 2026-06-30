const header = document.querySelector("[data-header]");
const navLinks = Array.from(document.querySelectorAll(".site-nav a"));
const switcherButtons = Array.from(document.querySelectorAll("[data-shot]"));
const shotPanels = Array.from(document.querySelectorAll("[data-shot-panel]"));

const setHeaderState = () => {
  header?.classList.toggle("is-scrolled", window.scrollY > 18);
};

setHeaderState();
window.addEventListener("scroll", setHeaderState, { passive: true });

if ("IntersectionObserver" in window && navLinks.length > 0) {
  const sections = navLinks
    .map((link) => document.querySelector(link.getAttribute("href")))
    .filter(Boolean);

  const observer = new IntersectionObserver(
    (entries) => {
      const visible = entries
        .filter((entry) => entry.isIntersecting)
        .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];

      if (!visible) return;

      navLinks.forEach((link) => {
        link.classList.toggle("is-active", link.getAttribute("href") === `#${visible.target.id}`);
      });
    },
    {
      rootMargin: "-36% 0px -48% 0px",
      threshold: [0.12, 0.32, 0.56],
    }
  );

  sections.forEach((section) => observer.observe(section));
}

switcherButtons.forEach((button) => {
  button.addEventListener("click", () => {
    const shot = button.dataset.shot;

    switcherButtons.forEach((item) => {
      const active = item === button;
      item.classList.toggle("is-active", active);
      item.setAttribute("aria-selected", String(active));
    });

    shotPanels.forEach((panel) => {
      panel.classList.toggle("is-visible", panel.dataset.shotPanel === shot);
    });
  });
});
