/**
 * Copyright (c) 2007-2015, Intelibo Ltd
 * 
 * Project:     ReddisDBAccess
 * Filename:    ReddisDBAccess.java
 * Author:      Elmira
 * Date:        10.03.2015
 * Description: 
 */
package intelibo.avtv.recommender;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;

import org.apache.mahout.cf.taste.impl.common.FastByIDMap;
import org.apache.mahout.cf.taste.impl.model.GenericUserPreferenceArray;
import org.apache.mahout.cf.taste.model.PreferenceArray;

import redis.clients.jedis.Jedis;
import redis.clients.jedis.JedisPool;
import redis.clients.jedis.JedisPoolConfig;
import redis.clients.jedis.exceptions.JedisException;

public class ReddisDBAccess
{
	private static final String RATING_PATTERN = "rating.vod.bulsat.*";
	private static final String RECOMMEND_PATTERN = "recommend.vod.bulsat.";
	private JedisPool _pool;
	private String _host;
	private int _port;
	
	public ReddisDBAccess(String host, int port)
	{
		_host = host;
		_port = port;
		
		JedisPoolConfig poolConfig = new JedisPoolConfig();
		_pool = new JedisPool(poolConfig, _host, _port, 0);
	}
	
	public void destroy()
	{
		if (_pool != null)
			_pool.destroy();
	}
	
	public FastByIDMap<PreferenceArray> getRatings()
	{
		
		Jedis jedis = _pool.getResource();
		FastByIDMap<PreferenceArray> userIdMap = new FastByIDMap<PreferenceArray>();
		try
		{
			
			Set<String> keys = jedis.keys(RATING_PATTERN);
			String[] keyArray = keys.toArray(new String[0]);
			List<String> result = jedis.mget(keyArray);
			for (int index = 0; index < keyArray.length; index++)
			{
				String key = keyArray[index];
				String id = key.substring(key.lastIndexOf('.') + 1);
				long userID = Long.parseLong(id.substring(0, id.indexOf(',')));
				long itemID = Long.parseLong(id.substring(id.lastIndexOf(',') + 1));
				long rating = Long.parseLong(result.get(index));
				PreferenceArray prefArray = null;
				if (userIdMap.containsKey(userID))
				{
					prefArray = userIdMap.get(userID);
					PreferenceArray newPrefs = new GenericUserPreferenceArray(prefArray.length() + 1);
					for (int i = 0, j = 1; i < prefArray.length(); i++, j++)
					{
						newPrefs.set(j, prefArray.get(i));
					}
					prefArray = newPrefs;
					
				}
				else
				{
					prefArray = new GenericUserPreferenceArray(1);
				}
				prefArray.setUserID(0, userID);
				prefArray.setItemID(0, itemID);
				prefArray.setValue(0, rating);
				userIdMap.put(userID, prefArray);
			}
			
		}
		catch (JedisException e)
		{
			if (null != jedis)
			{
				_pool.returnBrokenResource(jedis);
				jedis = null;
			}
			e.printStackTrace();
		}
		finally
		{
			if (null != jedis)
				_pool.returnResource(jedis);
		}
		return userIdMap;
	}
	
	public void addRecomendation(long userId, ArrayList<String> recomendList)
	{
		
		Jedis jedis = _pool.getResource();
		try
		{
			String key = RECOMMEND_PATTERN + userId;
			jedis.del(key);
			for (int index = 0; index < recomendList.size(); index++)
			{
				jedis.rpush(key, recomendList.get(index));
			}
		}
		catch (JedisException e)
		{
			if (null != jedis)
			{
				_pool.returnBrokenResource(jedis);
				jedis = null;
			}
			e.printStackTrace();
		}
		finally
		{
			if (null != jedis)
				_pool.returnResource(jedis);
		}
	}
	
}
