/**
 * Copyright (c) 2007-2015, Intelibo Ltd
 * 
 * Project:     MediaAdviser
 * Filename:    MediaAdviser.java
 * Author:      Elmira
 * Date:        10.03.2015
 * Description: Media recommender
 */

package intelibo.avtv.recommender;

import java.util.ArrayList;
import java.util.List;

import org.apache.mahout.cf.taste.model.DataModel;
import org.apache.mahout.cf.taste.model.PreferenceArray;
import org.apache.mahout.cf.taste.neighborhood.UserNeighborhood;
import org.apache.mahout.cf.taste.recommender.RecommendedItem;
import org.apache.mahout.cf.taste.recommender.Recommender;
import org.apache.mahout.cf.taste.similarity.ItemSimilarity;
import org.apache.mahout.cf.taste.similarity.UserSimilarity;
import org.apache.mahout.cf.taste.common.TasteException;
import org.apache.mahout.cf.taste.common.Weighting;
import org.apache.mahout.cf.taste.eval.RecommenderBuilder;
import org.apache.mahout.cf.taste.eval.RecommenderEvaluator;
import org.apache.mahout.cf.taste.impl.common.FastByIDMap;
import org.apache.mahout.cf.taste.impl.common.LongPrimitiveIterator;
import org.apache.mahout.cf.taste.impl.eval.AverageAbsoluteDifferenceRecommenderEvaluator;
import org.apache.mahout.cf.taste.impl.model.GenericDataModel;
import org.apache.mahout.cf.taste.impl.neighborhood.ThresholdUserNeighborhood;
import org.apache.mahout.cf.taste.impl.recommender.GenericItemBasedRecommender;
import org.apache.mahout.cf.taste.impl.recommender.GenericUserBasedRecommender;
import org.apache.mahout.cf.taste.impl.recommender.ItemAverageRecommender;
import org.apache.mahout.cf.taste.impl.recommender.ItemUserAverageRecommender;
import org.apache.mahout.cf.taste.impl.recommender.svd.ALSWRFactorizer;
import org.apache.mahout.cf.taste.impl.recommender.svd.SVDRecommender;
import org.apache.mahout.cf.taste.impl.similarity.PearsonCorrelationSimilarity;

public class MediaAdviser
{
	enum RecommenderType
	{
		UserRecommender, ItemRecommender, SVDRecommender, ItemAverageRecommender, ItemUserAverageRecommender
	}
	
	public static void main(String[] args)
	{
		try
		{
			if (args.length < 2)
			{
				System.out.println("Too few parameters");
				return;
			}
			String redisHost = args[0];
			
			int redisPort = Integer.valueOf(args[1]);
			
			RecommenderType recomenderType = null;
			
			RecommenderBuilder bestRecommender = null;
			
			ReddisDBAccess redis = new ReddisDBAccess(redisHost, redisPort);
			
			FastByIDMap<PreferenceArray> userIdMap = redis.getRatings();
			
			DataModel model = new GenericDataModel(userIdMap);
			
			RecommenderEvaluator evaluator = new AverageAbsoluteDifferenceRecommenderEvaluator();
			
			RecommenderBuilder userRecommenderBuilder = new RecommenderBuilder()
			{
				@Override
				public Recommender buildRecommender(DataModel model) throws TasteException
				{
					UserSimilarity similarity = new PearsonCorrelationSimilarity(model, Weighting.WEIGHTED);
					UserNeighborhood neighborhood = new ThresholdUserNeighborhood(0.85, similarity, model);
					return new GenericUserBasedRecommender(model, neighborhood, similarity);
				}
			};
			
			double bestScore = Double.MAX_VALUE;
			
			double score = evaluator.evaluate(userRecommenderBuilder, null, model, 0.95, 1);
			
			System.out.println("Evaluate user-based recommender with score " + score);
			
			if ((score != Double.NaN) && (bestScore > score))
			{
				bestScore = score;
				bestRecommender = userRecommenderBuilder;
				recomenderType = RecommenderType.UserRecommender;
			}
			
			RecommenderBuilder itemRecommenderBuilder = new RecommenderBuilder()
			{
				@Override
				public Recommender buildRecommender(DataModel model) throws TasteException
				{
					
					ItemSimilarity itemSimilarity = new PearsonCorrelationSimilarity(model, Weighting.WEIGHTED);
					return new GenericItemBasedRecommender(model, itemSimilarity);
				}
			};
			
			score = evaluator.evaluate(itemRecommenderBuilder, null, model, 0.95, 1);
			
			System.out.println("Evaluate item-based recommender with score " + score);
			
			if ((score != Double.NaN) && (bestScore > score))
			{
				bestScore = score;
				bestRecommender = itemRecommenderBuilder;
				recomenderType = RecommenderType.ItemRecommender;
			}
			
			RecommenderBuilder svdBuilder = new RecommenderBuilder()
			{
				@Override
				public Recommender buildRecommender(DataModel model) throws TasteException
				{
					return new SVDRecommender(model, new ALSWRFactorizer(model, 15, 0.05, 100));
				}
				
			};
			
			score = evaluator.evaluate(svdBuilder, null, model, 0.95, 1);
			
			System.out.println("Evaluate svd recommender with score " + score);
			
			if ((score != Double.NaN) && (bestScore > score))
			{
				bestScore = score;
				bestRecommender = svdBuilder;
				recomenderType = RecommenderType.SVDRecommender;
			}
			
			RecommenderBuilder aveargeItemBuilder = new RecommenderBuilder()
			{
				@Override
				public Recommender buildRecommender(DataModel model) throws TasteException
				{
					return new ItemAverageRecommender(model);
				}
				
			};
			
			score = evaluator.evaluate(aveargeItemBuilder, null, model, 0.95, 1);
			
			System.out.println("Evaluate average item recommender with score " + score);
			
			if ((score != Double.NaN) && (bestScore > score))
			{
				bestScore = score;
				bestRecommender = aveargeItemBuilder;
				recomenderType = RecommenderType.ItemAverageRecommender;
			}
			
			// / user recommendation is avg user - global avg item + avg item
			RecommenderBuilder aveargeUserBuilder = new RecommenderBuilder()
			{
				@Override
				public Recommender buildRecommender(DataModel model) throws TasteException
				{
					return new ItemUserAverageRecommender(model);
				}
				
			};
			
			score = evaluator.evaluate(aveargeUserBuilder, null, model, 0.95, 1);
			
			System.out.println("Evaluate average user recommender with score " + score);
			
			if ((score != Double.NaN) && (bestScore > score))
			{
				bestScore = score;
				bestRecommender = aveargeUserBuilder;
				recomenderType = RecommenderType.ItemUserAverageRecommender;
			}
			
			if (Double.MAX_VALUE != bestScore)
			{
				System.out.println("Selected " + recomenderType.name());
				printRecommendation(bestRecommender.buildRecommender(model), model, redis);
			}
			else
				System.out.println("No recommedations found....");
			
			redis.destroy();
		}
		catch (TasteException e)
		{
			// TODO Auto-generated catch block
			e.printStackTrace();
		}
	}
	
	private static void printRecommendation(Recommender recommender, DataModel model, ReddisDBAccess redis)
	        throws TasteException
	{
		
		for (LongPrimitiveIterator it = model.getUserIDs(); it.hasNext();)
		{
			long userId = it.nextLong();
			
			List<RecommendedItem> recommendations = recommender.recommend(userId, 10);
			
			if (recommendations.size() == 0)
			{
				continue;
			}
			ArrayList<String> recomendList = new ArrayList<String>();
			
			for (RecommendedItem recommendedItem : recommendations)
			{
				if (recommendedItem.getValue() > 0)
					recomendList.add(String.format("%d", recommendedItem.getItemID()));
			}
			
			redis.addRecomendation(userId, recomendList);
		}
		
	}
	
}
