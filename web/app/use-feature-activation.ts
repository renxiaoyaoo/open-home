"use client";

import { useEffect, useState } from "react";

type Feature = "gate" | "dryer" | "lock" | "auto";

export function useFeatureActivation(feature: Feature, activeByDefault: boolean) {
  const [active, setActive] = useState(activeByDefault);
  useEffect(() => {
    const update = () => {
      const hash = window.location.hash;
      setActive(hash ? hash === `#feature-${feature}-target` : activeByDefault);
    };
    update();
    window.addEventListener("hashchange", update);
    return () => window.removeEventListener("hashchange", update);
  }, [activeByDefault, feature]);
  return active;
}
