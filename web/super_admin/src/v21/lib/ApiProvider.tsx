import {createContext,useContext} from 'react';
import type {ReactNode} from 'react';
import {V21ApiClient} from './apiClient';

const ApiContext=createContext<V21ApiClient|null>(null);
export function V21ApiProvider({client,children}:{client:V21ApiClient;children:ReactNode}){
 return <ApiContext.Provider value={client}>{children}</ApiContext.Provider>;
}
export function useV21Api():V21ApiClient {
 const value=useContext(ApiContext);
 if(!value)throw new Error('V21ApiProvider is required for administrator API calls');
 return value;
}
