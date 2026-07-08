import { useConvexAuth } from "convex/react";
import { AuthScreen, ShellLoading } from "./AuthScreen";
import { VaultApp } from "./VaultApp";

export default function App() {
  const { isAuthenticated, isLoading } = useConvexAuth();

  if (isLoading) {
    return <ShellLoading />;
  }

  if (!isAuthenticated) {
    return <AuthScreen />;
  }

  return <VaultApp />;
}
