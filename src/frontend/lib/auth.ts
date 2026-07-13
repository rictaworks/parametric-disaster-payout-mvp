import NextAuth, { type NextAuthOptions } from 'next-auth';
import GoogleProvider from 'next-auth/providers/google';

export const authOptions: NextAuthOptions = {
  secret: process.env.NEXTAUTH_SECRET ?? 'dev-nextauth-secret',
  providers: [
    GoogleProvider({
      clientId: process.env.GOOGLE_CLIENT_ID ?? 'test-client-id',
      clientSecret: process.env.GOOGLE_CLIENT_SECRET ?? 'test-client-secret'
    })
  ],
  session: {
    strategy: 'jwt'
  },
  callbacks: {
    async jwt({ token, profile }) {
      const googleSub = typeof profile?.sub === 'string' ? profile.sub : token.googleSub;
      if (googleSub) {
        token.googleSub = googleSub;
      }
      return token;
    },
    async session({ session, token }) {
      session.googleSub = token.googleSub;
      return session;
    }
  }
};

const handler = NextAuth(authOptions);

export { handler as GET, handler as POST };
